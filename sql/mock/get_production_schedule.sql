-- the return type changes with the model, so the old one goes first
drop function if exists mock.get_production_schedule(timestamp with time zone, text, text, integer[], integer);

create function mock.get_production_schedule(p_until timestamp with time zone DEFAULT now(), p_step text DEFAULT 'print'::text, p_line_type text DEFAULT NULL::text, p_tenant_ids integer[] DEFAULT NULL::integer[], p_domain_id integer DEFAULT 1) returns TABLE(tenant_id integer, tenant_name text, production_company_id integer, resource_uid text, resource_name text, resource_path ltree, lane_id bigint, step text, level smallint, lane_item_id bigint, sort_order numeric, is_pinned boolean, no_split boolean, is_fixed_group text, start_offset_in_seconds integer, duration_in_seconds integer, start_at timestamp with time zone, end_at timestamp with time zone, nest_ids bigint[], nest_count integer, batch_id integer, batch_name text, material_id integer, material_name text, impact_json jsonb, sqm numeric, gross_sqm numeric, part_status_json jsonb, state_json jsonb, group_state_json jsonb, class_names text[], param_json jsonb)
	stable
	language plpgsql
as $$
#variable_conflict use_column
declare
    v_zone constant text := 'Europe/Amsterdam';
    -- the plan date is the day of the viewed moment; the axis of the board is
    -- that day's local midnight, offsets are seconds since then
    v_date       date := (p_until at time zone 'Europe/Amsterdam')::date;
    v_day_start  timestamp with time zone;
    v_day_end    timestamp with time zone;
    -- the open steps the plan side counts; a lookup later
    v_status_sequences constant integer[] := array[225, 290, 300, 350, 400, 450];
    -- print seconds per gross sqm at standard speed, and the shortest item; a lookup later
    v_standard_seconds_per_sqm constant numeric := 45;
    v_min_duration_in_seconds  constant integer := 900;
    -- legacy.nest width/height are in cm; a lookup later
    v_nest_size_per_sqm        constant numeric := 10000;
    v_state_lookup             jsonb;
begin
    select lk.lookup_json into v_state_lookup
    from relation.lookup lk where lk.lookup = 'lookup_resource_state';

    v_day_start := v_date::timestamp at time zone v_zone;
    v_day_end   := (v_date + 1)::timestamp at time zone v_zone;

    return query
    with the_plan as (
        -- the newest production plan of the day that covers the step
        select p.plan_id
        from action.plan p
        where p.plan_date = v_date
          and p.type = 'production-plan'
          and p_step = any (p.steps)
          and (p_line_type is null or p.line_type = p_line_type)
        order by p.plan_id desc
        limit 1
    ),
    tenant as (
        select (v.value ->> 'tenant_id')::integer             as tenant_id,
               v.value ->> 'name'                             as tenant_name,
               v.value ->> 'abb'                              as abb,
               (v.value ->> 'production_company_id')::integer as production_company_id
        from relation.lookup lk
        cross join lateral jsonb_array_elements(lk.lookup_json) as v(value)
        where lk.lookup = 'lookup_tenants'
    ),
    -- one lane = one machine's day; the live resource is found on its
    -- path, the tenant through its production line. Which machines a plan
    -- shows says plan_lane (a foil plan can carry a printer from the sheet
    -- hall; both boards share the lane and see its full occupation).
    lane as (
        select l.lane_id, pl_l.sort_order, l.resource_path,
               r.resource_uid, r.resource_name, r.step,
               t.tenant_id, t.tenant_name, t.production_company_id
        from the_plan tp
        join action.plan_lane pl_l on pl_l.plan_id = tp.plan_id
        join action.lane l on l.lane_id = pl_l.lane_id
        join relation.resource r on r.resource_path = l.resource_path
        -- the site is the first label of the path: the tenant's abb (dk, bh)
        left join tenant t on t.abb = ltree2text(subpath(l.resource_path, 0, 1))
        where l.resource_path is not null
          and (p_tenant_ids is null or t.tenant_id = any (p_tenant_ids))
    ),
    -- planned items with the nests hung on them
    item as (
        select li.lane_item_id, li.lane_id, li.sort_order, li.is_pinned, li.no_split,
               li.is_fixed_group, li.start_offset_in_seconds, li.duration_in_seconds, li.level,
               (select array_agg(distinct nli.nest_id)
                from action.nest_lane_item nli
                where nli.lane_item_id = li.lane_item_id) as nest_ids
        from action.lane_item li
        join lane on lane.lane_id = li.lane_id
        where li.level = 0
    ),
    -- what the nests of an item say: the batch, the run (amount x area) and
    -- the least advanced status, which names the item's state
    item_nest as (
        select i.lane_item_id,
               min(n.batch_id)                                                          as batch_id,
               min(b.batch_name)                                                        as batch_name,
               sum(coalesce(n.amount, 1) * coalesce(n.width, 0) * coalesce(n.height, 0)) / v_nest_size_per_sqm as run_sqm,
               (array_agg(n.nest_json ->> 'internal_status_code' order by ist.sequence nulls last))[1] as internal_status_code
        from item i
        join action.nest_lane_item nli on nli.lane_item_id = i.lane_item_id
        join legacy.nest n on n.nest_id = nli.nest_id
        left join legacy.batch b on b.batch_id = n.batch_id
        left join mapping.internal_status ist on ist.code = n.nest_json ->> 'internal_status_code' and ist.domain_id = p_domain_id
        group by i.lane_item_id
    ),
    -- one aggregate call per distinct nest set (rows per material of the set)
    agg_rows as materialized (
        select ns.nest_ids, a.*
        from (select distinct i.nest_ids from item i where i.nest_ids is not null) ns
        cross join lateral mapping.get_production_orderline_aggregate(
                 p_from             => p_until,
                 p_date_type        => 'nest',
                 p_nest_ids         => ns.nest_ids,
                 p_status_sequences => v_status_sequences,
                 p_is_open          => true,
                 p_domain_id        => p_domain_id) a
    ),
    -- summed over the materials of the set; the material is named when the
    -- set has one, else null
    item_agg as (
        select r.nest_ids,
               sum(r.orderline_count)::integer as orderline_count,
               sum(r.sqm)                      as sqm,
               sum(r.gross_sqm)                as gross_sqm,
               jsonb_build_object(
                   'count',         sum((r.impact_json ->> 'count')::integer),
                   'amount',        sum((r.impact_json ->> 'amount')::numeric),
                   'sqm',           round(sum((r.impact_json ->> 'sqm')::numeric), 2),
                   'rework_count',  sum((r.impact_json ->> 'rework_count')::integer),
                   'rework_amount', sum((r.impact_json ->> 'rework_amount')::numeric),
                   'rework_sqm',    round(sum((r.impact_json ->> 'rework_sqm')::numeric), 2)) as impact_json,
               case when count(distinct r.material_id) = 1 then min(r.material_id) end   as material_id,
               case when count(distinct r.material_id) = 1 then min(r.material_name) end as material_name,
               -- the part statuses of the whole set, summed per status
               (select jsonb_agg(jsonb_build_object(
                           'sequence', x.sequence, 'internal_status_code', x.internal_status_code,
                           'class_names', x.class_names, 'i18n', x.i18n, 'amount', x.amount)
                        order by x.sequence)
                from (select (e.value ->> 'sequence')::integer   as sequence,
                             e.value ->> 'internal_status_code'  as internal_status_code,
                             e.value -> 'class_names'            as class_names,
                             e.value -> 'i18n'                   as i18n,
                             sum((e.value ->> 'amount')::numeric) as amount
                      from agg_rows b
                      cross join lateral jsonb_array_elements(b.part_status_json) as e(value)
                      where b.nest_ids = r.nest_ids
                      group by 1, 2, 3, 4) x)                                          as part_status_json,
               (select array_agg(distinct c order by c)
                from agg_rows b cross join lateral unnest(b.class_names) as c
                where b.nest_ids = r.nest_ids)                                          as class_names
        from agg_rows r
        group by r.nest_ids
    ),
    -- realized: the state blocks and the produced items of the lanes'
    -- resources, up to the viewed moment (the log functions clip to now())
    realized_state as (
        select s.resource_uid, s.state, s.group_state, s.start_at,
               s.duration_seconds, s.data, s.nest_name
        from log.get_resource_state(
                 (select array_agg(l.resource_uid) from lane l), v_day_start, least(p_until, v_day_end), null) s
    ),
    realized_produced as (
        select r.resource_uid, r.state, r.group_state, r.start_at,
               r.duration_seconds, r.data, r.nest_name
        from log.get_resource_produced(
                 (select array_agg(l.resource_uid) from lane l), v_day_start, least(p_until, v_day_end), null) r
    )
    -- planned rows: the lane's primary resource names the row
    select l.tenant_id, l.tenant_name, l.production_company_id,
           l.resource_uid, l.resource_name, l.resource_path, l.lane_id, l.step,
           i.level, i.lane_item_id, i.sort_order, i.is_pinned, i.no_split, i.is_fixed_group,
           i.start_offset_in_seconds,
           -- pv2's duration when it sent one, else the print time of the run
           -- (nest area x amount) at the resource's speed, never shorter
           -- than the minimum
           case when i.duration_in_seconds > 0 then i.duration_in_seconds
                else greatest(ceil(coalesce(nf.run_sqm, 0) * v_standard_seconds_per_sqm
                                   / coalesce(nullif(mock.get_resource_speed_factor(ag.material_id, l.resource_uid), 0), 1))::integer,
                              v_min_duration_in_seconds) end,
           v_day_start + make_interval(secs => i.start_offset_in_seconds),
           null::timestamp with time zone,
           coalesce(i.nest_ids, '{}'::bigint[]),
           coalesce(cardinality(i.nest_ids), 0),
           nf.batch_id, nf.batch_name,
           ag.material_id, ag.material_name,
           ag.impact_json, ag.sqm, ag.gross_sqm,
           coalesce(ag.part_status_json, '[]'::jsonb),
           -- the state of a planned item is the least advanced status of its
           -- nests, from the same lookup the realized rows use
           (select st.value from jsonb_array_elements(v_state_lookup) as ss(value)
                                 cross join lateral jsonb_array_elements(ss.value -> 'states') as st(value)
             where st.value ->> 'code' = coalesce(nf.internal_status_code, 'batch') limit 1),
           (select ss.value - 'states' from jsonb_array_elements(v_state_lookup) as ss(value)
                                       cross join lateral jsonb_array_elements(ss.value -> 'states') as st(value)
             where st.value ->> 'code' = coalesce(nf.internal_status_code, 'batch') limit 1),
           coalesce(ag.class_names, '{}'::text[]),
           jsonb_build_object(
               'standard_production_impact_in_seconds', ceil(coalesce(nf.run_sqm, 0) * v_standard_seconds_per_sqm)::integer,
               'run_sqm',                                round(coalesce(nf.run_sqm, 0), 2),
               'speed_factor',                           mock.get_resource_speed_factor(ag.material_id, l.resource_uid),
               'orderline_count',                        ag.orderline_count)
    from item i
    join lane l on l.lane_id = i.lane_id
    left join item_nest nf on nf.lane_item_id = i.lane_item_id
    left join item_agg ag on ag.nest_ids = i.nest_ids

    union all
    -- realized: state blocks, named by the resource that ran
    select l.tenant_id, l.tenant_name, l.production_company_id,
           l.resource_uid, l.resource_name, l.resource_path, l.lane_id, l.step,
           1::smallint, null::bigint, null::numeric, false, false, null::text,
           extract(epoch from (rs.start_at - v_day_start))::integer,
           rs.duration_seconds::integer,
           rs.start_at,
           rs.start_at + make_interval(secs => rs.duration_seconds),
           '{}'::bigint[], 0,
           null::integer, null::text,
           null::integer, null::text,
           null::jsonb, null::numeric, null::numeric,
           '[]'::jsonb,
           rs.state, rs.group_state,
           array_remove(array[rs.state ->> 'class_name'], null),
           coalesce(rs.data, '{}'::jsonb)
    from realized_state rs
    join lane l on l.resource_uid = rs.resource_uid

    union all
    -- realized: produced items, named by the resource that ran
    select l.tenant_id, l.tenant_name, l.production_company_id,
           l.resource_uid, l.resource_name, l.resource_path, l.lane_id, l.step,
           1::smallint, null::bigint, null::numeric, false, false, null::text,
           extract(epoch from (rp.start_at - v_day_start))::integer,
           rp.duration_seconds::integer,
           rp.start_at,
           rp.start_at + make_interval(secs => coalesce(rp.duration_seconds, 0)),
           case when (rp.data ->> 'nest_id') is not null then array[(rp.data ->> 'nest_id')::bigint] else '{}'::bigint[] end,
           case when (rp.data ->> 'nest_id') is not null then 1 else 0 end,
           (rp.data ->> 'batch_id')::integer, null::text,
           null::integer, null::text,
           null::jsonb, null::numeric, null::numeric,
           '[]'::jsonb,
           rp.state, rp.group_state,
           array_remove(array[rp.state ->> 'class_name', 'realized-produced'], null),
           coalesce(rp.data, '{}'::jsonb) || jsonb_build_object('nest_name', rp.nest_name)
    from realized_produced rp
    join lane l on l.resource_uid = rp.resource_uid

    order by tenant_id, resource_path, level, start_offset_in_seconds, sort_order;
end;
$$;

alter function mock.get_production_schedule(timestamp with time zone, text, text, integer[], integer) owner to xfw3;

-- the board query is planned per call and inlines the aggregate; JIT compiling
-- it costs seconds and never pays back
alter function mock.get_production_schedule(timestamp with time zone, text, text, integer[], integer) set jit = off;
