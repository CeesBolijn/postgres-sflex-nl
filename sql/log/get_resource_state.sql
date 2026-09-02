create function log.get_resource_state(p_resource_uids text[] DEFAULT NULL::text[], p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_until timestamp with time zone DEFAULT now(), p_line_type text DEFAULT NULL::text) returns TABLE(resource_uid text, state jsonb, group_state jsonb, layout_name text, step text, name text, nest_name text, filename text, page_number integer, batch_id integer, batch_name text, data jsonb, start_at timestamp with time zone, offset_seconds numeric, duration_seconds numeric)
	stable
	language plpgsql
as $$
declare
  v_lookup_json jsonb;
  v_day date;
begin
  v_day := coalesce(p_until::date, current_date);
  p_from := coalesce(p_from, (v_day::timestamp + interval '6 hours') at time zone 'Europe/Amsterdam');
  p_until := least(
               coalesce(p_until, (v_day + 1)::timestamp at time zone 'Europe/Amsterdam'),
               now()
             );

  if p_line_type is not null and array_length(p_resource_uids, 1) is null then
    select array_agg(res.resource_uid)
    into p_resource_uids
    from relation.resource res
    join relation.production_line pl on pl.line_id = res.line_id
    where pl.line_type = p_line_type;
  end if;

  -- the flat lookup with counts_as/alias_of lives in log.lookup
  select lk.lookup_json into v_lookup_json
  from log.lookup lk
  where lk.lookup = 'lookup_resource_state'
  limit 1;

  return query
  with
  state_map as (
    -- flat lookup: one node per state. alias_of resolves a source
    -- variant (starved.operator, blocked.operator) to the state it is;
    -- group_state is the resolved node itself, the hierarchy is gone
    select
      s.value ->> 'code'          as state_code,
      coalesce(t.value, s.value)  as state_json,
      coalesce(t.value, s.value)  as group_state_json
    from jsonb_array_elements(v_lookup_json) as s(value)
    left join jsonb_array_elements(v_lookup_json) as t(value)
      on t.value ->> 'code' = s.value ->> 'alias_of'
  ),
  -- last change per resource that starts before the window
  anchor as (
    select r.resource_uid, max(r.start_at) as start_at
    from log.state r
    where r.resource_uid = any(p_resource_uids)
      and r.start_at < p_from
    group by r.resource_uid
  ),
  -- single scan from the anchor up to p_until, with the next change for duration
  windowed as (
    select
      r.resource_uid,
      r.state,
      r.start_at,
      lead(r.start_at) over (partition by r.resource_uid order by r.start_at) as next_at
    from log.state r
    left join anchor a on a.resource_uid = r.resource_uid
    where r.resource_uid = any(p_resource_uids)
      and r.start_at < p_until
      and r.start_at >= coalesce(a.start_at, '-infinity'::timestamptz)
  )
  select
    w.resource_uid,
    sm.state_json,
    sm.group_state_json,
    res.resource_json ->> 'layout_name',
    res.resource_json ->> 'step',
    res.resource_json ->> 'name',
    null::text,      -- nest_name: not on log.state
    null::text,      -- filename: not on log.state
    null::integer,   -- page_number: not on log.state
    null::integer,
    null::text,
    null::jsonb,
    greatest(w.start_at, p_from),
    extract(epoch from (greatest(w.start_at, p_from) - p_from))::numeric,
    extract(epoch from (least(coalesce(w.next_at, p_until), p_until) - greatest(w.start_at, p_from)))::numeric
  from windowed w
  left join relation.resource res on res.resource_uid = w.resource_uid
  left join state_map sm on sm.state_code = w.state
  order by
    res.resource_json ->> 'step' desc,
    res.resource_json ->> 'name',
    greatest(w.start_at, p_from);
end;
$$;

alter function log.get_resource_state(text[], timestamp with time zone, timestamp with time zone, text) owner to xfw3;

