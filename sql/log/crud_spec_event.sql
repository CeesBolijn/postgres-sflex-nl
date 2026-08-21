create function crud_spec_event(p_param_json jsonb, p_no_results boolean DEFAULT false) returns TABLE(track_by integer, crud text, spec_id bigint, spec_event_id bigint)
	language plpgsql
as $$
declare
  rec jsonb;
  v_data jsonb;
  v_spec_id bigint;
  v_spec_event_id bigint;
  v_from_seq integer;
  v_to_seq integer;
begin

  for rec in
    select value from jsonb_array_elements(p_param_json) as e(value)
    where e.value ->> 'crud' = 'create'
    order by (e.value -> 'data' ->> 'to_status' = 'stock') desc,
             (e.value ->> 'track_by')::integer
  loop

    v_data := rec -> 'data';
    v_spec_id := null;
    v_spec_event_id := null;

    if v_data ->> 'to_status' = 'stock' then

      insert into log.spec as sp (amount, spec_json)
      values (
        (v_data ->> 'amount')::integer,
        (v_data -> 'spec_json') || jsonb_build_object('expiry_date', v_data ->> 'expiry_date')
      )
      returning sp.spec_id into v_spec_id;

    else

     select sp.spec_id into v_spec_id
     from log.spec sp
     where sp.spec_json -> 'resource_uids' ->> 0 = v_data ->> 'resource_uid'
     and sp.spec_json ->> 'ink_configuration_id'
       = v_data -> 'spec_json' ->> 'ink_configuration_id'
     order by sp.spec_id desc
     limit 1;

      v_from_seq := (select st.sequence from job.status st where st.code = v_data ->> 'from_status');
      v_to_seq := (select st.sequence from job.status st where st.code = v_data ->> 'to_status');

      -- skip rows we can't log: unknown spec, no resolvable status, or a non-move
      if v_spec_id is null
         or (v_from_seq is null and v_to_seq is null)
         or v_from_seq is not distinct from v_to_seq then
        continue;
      end if;

      insert into log.spec_event as sl (
        spec_id, from_status_sequence, to_status_sequence,
        amount, remaining_impact_delta, resource_uids, moved_at
      )
      values (
        v_spec_id, v_from_seq, v_to_seq,
        (v_data ->> 'amount')::integer, null,
        array[v_data ->> 'resource_uid'],
        (v_data ->> 'moved_at')::timestamptz
      )
      returning sl.spec_event_id into v_spec_event_id;

    end if;

    if not p_no_results then
      return query select
        (rec ->> 'track_by')::integer,
        rec ->> 'crud',
        v_spec_id,
        v_spec_event_id;
    end if;

  end loop;

end;
$$;

alter function crud_spec_event(jsonb, boolean) owner to xfw3;

