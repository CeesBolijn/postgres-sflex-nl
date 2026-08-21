create function crud_spec_event(p_param_json jsonb, p_no_results boolean DEFAULT false) returns TABLE(track_by integer, crud text, spec_id bigint, spec_event_id bigint)
	language plpgsql
as $$
#variable_conflict use_column
begin

  -- 1. stock rows create a spec. These run first: movements in the same
  --    call find their spec by newest spec_id, which may be created here.
  --    Inserted ids are paired back to input rows by rank; spec_id is
  --    assigned in the ordered insert's row order.
  return query
  with stock as (
      select (e.value ->> 'track_by')::integer as track_by,
             e.value ->> 'crud'                as crud,
             e.value -> 'data'                 as data,
             row_number() over (order by (e.value ->> 'track_by')::integer) as rn
      from jsonb_array_elements(p_param_json) as e(value)
      where e.value ->> 'crud' = 'create'
        and e.value -> 'data' ->> 'to_status' = 'stock'
  ),
  ins as (
      insert into log.spec as sp (amount, spec_json)
      select (s.data ->> 'amount')::integer,
             (s.data -> 'spec_json') || jsonb_build_object('expiry_date', s.data ->> 'expiry_date')
      from stock s
      order by s.rn
      returning sp.spec_id
  ),
  ins_ranked as (
      select i.spec_id, row_number() over (order by i.spec_id) as rn
      from ins i
  )
  select s.track_by, s.crud, i.spec_id, null::bigint
  from stock s
  join ins_ranked i on i.rn = s.rn
  where not p_no_results
  order by s.track_by;

  -- 2. the other rows are movements; the specs inserted above are visible
  --    here. Rows that cannot be logged (unknown spec, no resolvable
  --    status, or a non-move) are silently omitted from the result.
  return query
  with move as (
      select (e.value ->> 'track_by')::integer as track_by,
             e.value ->> 'crud'                as crud,
             e.value -> 'data'                 as data
      from jsonb_array_elements(p_param_json) as e(value)
      where e.value ->> 'crud' = 'create'
        and e.value -> 'data' ->> 'to_status' is distinct from 'stock'
  ),
  resolved as (
      select m.track_by, m.crud, m.data,
             cand.spec_id, f.sequence as from_seq, t.sequence as to_seq
      from move m
      left join lateral (
          select sp.spec_id
          from log.spec sp
          where sp.spec_json -> 'resource_uids' ->> 0 = m.data ->> 'resource_uid'
            and sp.spec_json ->> 'ink_configuration_id'
              = m.data -> 'spec_json' ->> 'ink_configuration_id'
          order by sp.spec_id desc
          limit 1
      ) cand on true
      left join job.status f on f.code = m.data ->> 'from_status'
      left join job.status t on t.code = m.data ->> 'to_status'
  ),
  valid as (
      select r.*, row_number() over (order by r.track_by) as rn
      from resolved r
      where r.spec_id is not null
        and (r.from_seq is not null or r.to_seq is not null)
        and r.from_seq is distinct from r.to_seq
  ),
  ins as (
      insert into log.spec_event as sl (
          spec_id, from_status_sequence, to_status_sequence,
          amount, remaining_impact_delta, resource_uids, moved_at
      )
      select v.spec_id, v.from_seq, v.to_seq,
             (v.data ->> 'amount')::integer, null,
             array[v.data ->> 'resource_uid'],
             (v.data ->> 'moved_at')::timestamptz
      from valid v
      order by v.rn
      returning sl.spec_event_id
  ),
  ins_ranked as (
      select i.spec_event_id, row_number() over (order by i.spec_event_id) as rn
      from ins i
  )
  select v.track_by, v.crud, v.spec_id, i.spec_event_id
  from valid v
  join ins_ranked i on i.rn = v.rn
  where not p_no_results
  order by v.track_by;

end;
$$;

alter function crud_spec_event(jsonb, boolean) owner to xfw3;
