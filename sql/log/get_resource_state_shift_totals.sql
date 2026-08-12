create function get_resource_state_shift_totals(p_resource_uids text[] DEFAULT NULL::text[], p_until timestamp with time zone DEFAULT CURRENT_TIMESTAMP, p_days integer DEFAULT 42, p_line_type text DEFAULT NULL::text, p_states text[] DEFAULT NULL::text[], p_include_weekends boolean DEFAULT false, p_include_mandatory_days_off boolean DEFAULT false, p_include_shifts boolean DEFAULT true, p_group_by text DEFAULT NULL::text) returns TABLE(shift_date date, shift_index integer, shift_start timestamp with time zone, shift_end timestamp with time zone, resource_uid text, resource_name text, resource_uids jsonb, line text, step text, state text, state_json jsonb, duration_seconds numeric, total_duration_seconds numeric, duration_percent numeric, parent_percent numeric, count_resources integer, sort_order integer)
	stable
	parallel safe
	language plpgsql
as $$
#variable_conflict use_column
declare
  v_lookup_json jsonb;
  v_step_category_json jsonb;
  v_until date := (p_until at time zone 'Europe/Amsterdam')::date;
  v_all_resources boolean := (p_resource_uids is null or array_length(p_resource_uids, 1) is null);
  v_group_by text := coalesce(p_group_by, case when v_all_resources then 'step' else 'resource' end);
  v_keep_resource boolean;
  v_keep_step boolean;
  v_excluded_states text[] := array['offline','planned'];
begin
  if v_group_by not in ('resource', 'step', 'line') then
    raise exception 'invalid p_group_by %, expected one of: resource, step, line', v_group_by;
  end if;

  v_keep_resource := (v_group_by = 'resource');
  v_keep_step     := (v_group_by in ('resource', 'step'));

  if v_all_resources then
    select array_agg(res.resource_uid)
    into p_resource_uids
    from relation.resource res
    left join relation.production_line pl on pl.line_id = res.line_id
    where p_line_type is null or pl.line_type = p_line_type;
  end if;

  v_excluded_states := array(
    select e from unnest(v_excluded_states) as e
    where p_states is null or e <> all(p_states)
  );

  select lk.lookup_json into v_lookup_json
  from relation.lookup lk where lk.lookup = 'lookup_resource_state' limit 1;

  select lk.lookup_json into v_step_category_json
  from relation.lookup lk where lk.lookup = 'lookup_step_category' limit 1;

  return query
  with
  state_map as (
    select g.value ->> 'code' as state_code, null::text as parent_code, g.value as state_json,
           (g.value ->> 'order')::int as group_order,
           (g.value ->> 'order')::int as state_order
    from jsonb_array_elements(v_lookup_json) as g(value)
    where g.value ->> 'group' = 'state'
    union all
    select s.value ->> 'code', g.value ->> 'code', s.value,
           (g.value ->> 'order')::int,
           (s.value ->> 'order')::int
    from jsonb_array_elements(v_lookup_json) as g(value),
         jsonb_array_elements(g.value -> 'states') as s(value)
    where s.value ->> 'group' = 'state'
  ),
  step_order as (
    select so.value ->> 'step' as step, (so.value ->> 'order')::int as step_order
    from jsonb_array_elements(v_step_category_json) as so(value)
  ),
  resources as (
    select res.resource_uid, res.resource_name, res.step, pl.line
    from relation.resource res
    left join relation.production_line pl on pl.line_id = res.line_id
    where res.resource_uid = any(p_resource_uids)
  ),
  shift_def as (
    select d.date as shift_date,
           sh.idx::int as shift_index,
           (d.date + (sh.value ->> 'start_time')::time)
             at time zone 'Europe/Amsterdam' as shift_start,
           (d.date + (sh.value ->> 'end_time')::time
              + case when (sh.value ->> 'end_time')::time <= (sh.value ->> 'start_time')::time
                     then interval '1 day' else interval '0' end)
             at time zone 'Europe/Amsterdam' as shift_end
    from action.dates d
    cross join lateral jsonb_array_elements(d.shift_json) with ordinality as sh(value, idx)
    where d.date between v_until - p_days + 1 and v_until
      and (p_include_weekends or not d.is_weekend)
      and (p_include_mandatory_days_off or not coalesce(d.is_mandatory_day_off, false))
  ),
  actual as (
    select agg.shift_date, agg.shift_index, agg.shift_start, agg.shift_end,
           agg.resource_uid, res.resource_name, pl.line, res.step, agg.state,
           sum(agg.duration_seconds)::numeric as seconds
    from log.state_shift_agg agg
    join relation.resource res on res.resource_uid = agg.resource_uid
    left join relation.production_line pl on pl.line_id = res.line_id
    join action.dates d on d.date = agg.shift_date
    where agg.shift_date between v_until - p_days + 1 and v_until
      and agg.resource_uid = any(p_resource_uids)
      and (p_include_weekends or not d.is_weekend)
      and (p_include_mandatory_days_off or not coalesce(d.is_mandatory_day_off, false))
    group by agg.shift_date, agg.shift_index, agg.shift_start, agg.shift_end,
             agg.resource_uid, res.resource_name, pl.line, res.step, agg.state
  ),
  events as (
    select shift_date, shift_index, shift_start, shift_end,
           resource_uid, resource_name, line, step, state, seconds
    from actual
    union all
    select sd.shift_date, sd.shift_index, sd.shift_start, sd.shift_end,
           r.resource_uid, r.resource_name, r.line, r.step, 'idle',
           extract(epoch from (sd.shift_end - sd.shift_start))::numeric
    from shift_def sd
    cross join resources r
    where not exists (
      select 1 from actual a
      where a.resource_uid = r.resource_uid
        and a.shift_date = sd.shift_date
        and a.shift_index = sd.shift_index
    )
  ),
  base as (
    select e.shift_date,
           case when p_include_shifts then e.shift_index else null::int end as shift_index,
           case when v_keep_resource then e.resource_uid else null::text end as resource_uid,
           case when v_keep_resource then e.resource_name else null::text end as resource_name,
           e.line,
           case when v_keep_step then e.step else null::text end as step,
           e.state,
           sum(e.seconds)::numeric as seconds,
           min(e.shift_start) as shift_start,
           max(e.shift_end) as shift_end
    from events e
    group by e.shift_date,
             case when p_include_shifts then e.shift_index else null::int end,
             case when v_keep_resource then e.resource_uid else null::text end,
             case when v_keep_resource then e.resource_name else null::text end,
             e.line,
             case when v_keep_step then e.step else null::text end,
             e.state
  ),
  child_totals as (
    select b.shift_date, b.shift_index, b.resource_uid, b.step, b.line,
           sm.parent_code, sum(b.seconds)::numeric as children_seconds
    from base b
    join state_map sm on sm.state_code = b.state
    where sm.parent_code is not null
      and b.state <> all(v_excluded_states)
      and (p_states is null or b.state = any(p_states))
    group by b.shift_date, b.shift_index, b.resource_uid, b.step, b.line, sm.parent_code
  ),
  resource_counts as (
    select e.shift_date,
           case when p_include_shifts then e.shift_index else null::int end as shift_index,
           case when v_keep_resource then e.resource_uid else null::text end as resource_uid,
           case when v_keep_step then e.step else null::text end as step,
           e.line,
           count(distinct e.resource_uid)::integer as count_resources
    from events e
    where e.state <> all(v_excluded_states)
    group by e.shift_date,
             case when p_include_shifts then e.shift_index else null::int end,
             case when v_keep_resource then e.resource_uid else null::text end,
             case when v_keep_step then e.step else null::text end,
             e.line
  ),
  computed as (
    select b.shift_date, b.shift_index,
           min(b.shift_start) over w as shift_start,
           max(b.shift_end)   over w as shift_end,
           b.resource_uid, b.resource_name, b.line, b.step,
           CASE
            WHEN b.state = 'starved.operator' THEN 'starved'
            WHEN b.state = 'blocked.operator' THEN 'blocked' ELSE b.state END as state,
           sm.state_json,
           sm.group_order, sm.state_order,
           greatest(b.seconds - coalesce(ct.children_seconds, 0), 0)::numeric as seconds,
           sum(b.seconds) filter (where sm.parent_code is null and b.state <> all(v_excluded_states)) over w as total_duration_seconds,
           case when sm.parent_code is not null and b.state <> all(v_excluded_states)
                then round(b.seconds / nullif(par.seconds, 0) * 100, 2) end as parent_percent,
           coalesce(rc.count_resources, 0) as count_resources
    from base b
    left join state_map sm on sm.state_code = b.state
    left join child_totals ct
      on ct.shift_date = b.shift_date
     and ct.shift_index is not distinct from b.shift_index
     and ct.resource_uid is not distinct from b.resource_uid
     and ct.step is not distinct from b.step
     and ct.line is not distinct from b.line
     and ct.parent_code = b.state
    left join base par
      on par.shift_date = b.shift_date
     and par.shift_index is not distinct from b.shift_index
     and par.resource_uid is not distinct from b.resource_uid
     and par.step is not distinct from b.step
     and par.line is not distinct from b.line
     and par.state = sm.parent_code
    left join resource_counts rc
      on rc.shift_date = b.shift_date
     and rc.shift_index is not distinct from b.shift_index
     and rc.resource_uid is not distinct from b.resource_uid
     and rc.step is not distinct from b.step
     and rc.line is not distinct from b.line
    window w as (partition by b.shift_date, b.shift_index, b.step, b.resource_uid, b.line)
  )
  select c.shift_date,
         coalesce(c.shift_index, 1) as shift_index,
         c.shift_start, c.shift_end,
         c.resource_uid, c.resource_name,
         (select jsonb_agg(r.resource_uid order by r.resource_uid)
             from resources r
             where r.line = c.line
               and (c.step is null or r.step = c.step)) as resource_uids,
         c.line, c.step, c.state, c.state_json,
         c.seconds,
         c.total_duration_seconds,
         case when c.state <> all(v_excluded_states)
              then round(c.seconds / nullif(c.total_duration_seconds, 0) * 100, 2) end as duration_percent,
         c.parent_percent,
         c.count_resources,
         c.state_order
  from computed c
  left join step_order so on so.step = c.step
  where p_states is null or c.state = any(p_states) or c.state = 'planned'
  order by so.step_order nulls last, c.step, c.line, c.resource_name, c.shift_date, c.shift_index, c.state_order;
end;
$$;

alter function get_resource_state_shift_totals(text[], timestamp with time zone, integer, text, text[], boolean, boolean, boolean, text) owner to xfw3;

