create function log.get_resource_state_shift_totals(p_resource_uids text[] DEFAULT NULL::text[], p_until timestamp with time zone DEFAULT CURRENT_TIMESTAMP, p_days integer DEFAULT 42, p_line_type text DEFAULT NULL::text, p_states text[] DEFAULT NULL::text[], p_include_weekends boolean DEFAULT false, p_include_mandatory_days_off boolean DEFAULT false, p_include_shifts boolean DEFAULT true, p_group_by text DEFAULT NULL::text, p_tenant_ids integer[] DEFAULT NULL::integer[]) returns TABLE(shift_date date, shift_index integer, shift_start timestamp with time zone, shift_end timestamp with time zone, resource_uid text, resource_name text, resource_uids jsonb, line text, step text, state text, state_json jsonb, duration_seconds numeric, duration_percentage numeric, param_json jsonb, oee_json jsonb, count_resources integer, sort_order integer)
	stable
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
  -- the OEE formulas. The bucket totals (counts_as in
  -- lookup_resource_state) go into param_json per group and
  -- evaluate_many_nas runs these lines over them. A state without a
  -- counts_as sits inside production_hours without being summed:
  -- that is the not-producing loss
  v_formula_json jsonb := jsonb_build_array(
      'production_hours = total_shift_hours - (breakdown_hours + offline_hours)',
      'producing_oee = production_hours > 0 ? producing_hours / production_hours * 100 : 0',
      'breakdown_percentage = total_shift_hours > 0 ? breakdown_hours / total_shift_hours * 100 : 0',
      'offline_percentage = total_shift_hours > 0 ? offline_hours / total_shift_hours * 100 : 0',
      'planned_percentage = total_shift_hours > 0 ? planned_hours / total_shift_hours * 100 : 0');
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

  -- the flat lookup with counts_as lives in log.lookup for now;
  -- relation.lookup keeps the old nested form until every reader
  -- has moved over
  select lk.lookup_json into v_lookup_json
  from log.lookup lk where lk.lookup = 'lookup_resource_state' limit 1;

  select lk.lookup_json into v_step_category_json
  from relation.lookup lk where lk.lookup = 'lookup_step_category' limit 1;

  return query
  with
  -- flat lookup: one node per state; alias_of resolves a source
  -- variant (starved.operator, blocked.operator) to the state it is
  state_map as (
    select s.value ->> 'code'                                          as state_code,
           coalesce(t.value ->> 'code', s.value ->> 'code')            as effective_code,
           coalesce(t.value, s.value)                                  as state_json,
           coalesce((t.value ->> 'order')::int, (s.value ->> 'order')::int) as state_order,
           coalesce(t.value ->> 'counts_as', s.value ->> 'counts_as')  as counts_as
    from jsonb_array_elements(v_lookup_json) as s(value)
    left join jsonb_array_elements(v_lookup_json) as t(value)
      on t.value ->> 'code' = s.value ->> 'alias_of'
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
      and (p_include_mandatory_days_off or not (coalesce(p_tenant_ids, d.tenants_mandatory_day_off) <@ d.tenants_mandatory_day_off and d.tenants_mandatory_day_off <> '{}'))
  ),
  actual as (
    select agg.shift_date, agg.shift_index, agg.shift_start, agg.shift_end,
           agg.resource_uid, res.resource_name, pl.line, res.step,
           coalesce(sm.effective_code, agg.state) as state,
           sum(agg.duration_seconds)::numeric as seconds
    from log.state_shift_agg agg
    join relation.resource res on res.resource_uid = agg.resource_uid
    left join relation.production_line pl on pl.line_id = res.line_id
    join action.dates d on d.date = agg.shift_date
    left join state_map sm on sm.state_code = agg.state
    where agg.shift_date between v_until - p_days + 1 and v_until
      and agg.resource_uid = any(p_resource_uids)
      and (p_include_weekends or not d.is_weekend)
      and (p_include_mandatory_days_off or not (coalesce(p_tenant_ids, d.tenants_mandatory_day_off) <@ d.tenants_mandatory_day_off and d.tenants_mandatory_day_off <> '{}'))
    group by agg.shift_date, agg.shift_index, agg.shift_start, agg.shift_end,
             agg.resource_uid, res.resource_name, pl.line, res.step,
             coalesce(sm.effective_code, agg.state)
  ),
  events as (
    select shift_date, shift_index, shift_start, shift_end,
           resource_uid, resource_name, line, step, state, seconds
    from actual
    union all
    -- a resource with no rows in a shift still gets the full window as
    -- idle, so the group stays visible and its OEE reads 0
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
  -- the denominator: window length times resources, from the shift
  -- definition alone — never from what happens to be logged
  totals as (
    select sd.shift_date,
           case when p_include_shifts then sd.shift_index else null::int end as shift_index,
           case when v_keep_resource then r.resource_uid else null::text end as resource_uid,
           case when v_keep_step then r.step else null::text end as step,
           r.line,
           sum(extract(epoch from (sd.shift_end - sd.shift_start)))::numeric as total_seconds,
           count(distinct r.resource_uid)::integer as count_resources
    from shift_def sd
    cross join resources r
    group by sd.shift_date,
             case when p_include_shifts then sd.shift_index else null::int end,
             case when v_keep_resource then r.resource_uid else null::text end,
             case when v_keep_step then r.step else null::text end,
             r.line
  ),
  bucket_sums as (
    select b.shift_date, b.shift_index, b.resource_uid, b.step, b.line,
           sum(b.seconds) filter (where sm.counts_as = 'producing') as producing_seconds,
           sum(b.seconds) filter (where sm.counts_as = 'breakdown') as breakdown_seconds,
           sum(b.seconds) filter (where sm.counts_as = 'offline')   as offline_seconds,
           sum(b.seconds) filter (where sm.counts_as = 'planned')   as planned_seconds
    from base b
    left join state_map sm on sm.state_code = b.state
    group by b.shift_date, b.shift_index, b.resource_uid, b.step, b.line
  ),
  oee as (
    select t.shift_date, t.shift_index, t.resource_uid, t.step, t.line,
           t.total_seconds, t.count_resources,
           ev.param_json,
           public.evaluate_many_nas(v_formula_json, ev.param_json) as oee_json
    from totals t
    left join bucket_sums bs
      on bs.shift_date = t.shift_date
     and bs.shift_index is not distinct from t.shift_index
     and bs.resource_uid is not distinct from t.resource_uid
     and bs.step is not distinct from t.step
     and bs.line is not distinct from t.line
    cross join lateral (
      select jsonb_build_object(
                 'total_shift_hours', round(t.total_seconds / 3600.0, 4),
                 'producing_hours',   round(coalesce(bs.producing_seconds, 0) / 3600.0, 4),
                 'breakdown_hours',   round(coalesce(bs.breakdown_seconds, 0) / 3600.0, 4),
                 'offline_hours',     round(coalesce(bs.offline_seconds, 0) / 3600.0, 4),
                 'planned_hours',     round(coalesce(bs.planned_seconds, 0) / 3600.0, 4)
             ) as param_json
    ) ev
  )
  select b.shift_date,
         coalesce(b.shift_index, 1) as shift_index,
         b.shift_start, b.shift_end,
         b.resource_uid, b.resource_name,
         (select jsonb_agg(r.resource_uid order by r.resource_uid)
             from resources r
             where r.line = b.line
               and (b.step is null or r.step = b.step)) as resource_uids,
         b.line, b.step, b.state,
         sm.state_json,
         b.seconds,
         round(b.seconds / nullif(o.total_seconds, 0) * 100, 2) as duration_percentage,
         o.param_json,
         o.oee_json,
         o.count_resources,
         sm.state_order
  from base b
  left join state_map sm on sm.state_code = b.state
  join oee o
    on o.shift_date = b.shift_date
   and o.shift_index is not distinct from b.shift_index
   and o.resource_uid is not distinct from b.resource_uid
   and o.step is not distinct from b.step
   and o.line is not distinct from b.line
  left join step_order so on so.step = b.step
  where p_states is null or b.state = any(p_states) or b.state = 'planned'
  order by so.step_order nulls last, b.step, b.line, b.resource_name, b.shift_date, b.shift_index, sm.state_order;
end;
$$;

alter function log.get_resource_state_shift_totals(text[], timestamp with time zone, integer, text, text[], boolean, boolean, boolean, text, integer[]) owner to xfw3;
