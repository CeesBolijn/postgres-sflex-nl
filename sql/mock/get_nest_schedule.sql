-- return type changes, so the old signature has to go first
drop function if exists mock.get_nest_schedule(timestamp with time zone, text, text, integer[], boolean, integer, integer, integer);
drop function if exists mock.get_nest_schedule(timestamp with time zone, text, text, integer[], integer, integer, integer);

create function mock.get_nest_schedule(p_until timestamp with time zone DEFAULT now(), p_step text DEFAULT 'print'::text, p_line_type text DEFAULT NULL::text, p_tenant_ids integer[] DEFAULT NULL::integer[], p_look_back_days integer DEFAULT 0, p_look_ahead_days integer DEFAULT 0, p_domain_id integer DEFAULT 1) returns TABLE(material_id integer, material_name text, production_line_id integer, tenant_id integer, tenant_name text, production_company_id integer, resource_uid text, resource_name text, delivery_hours integer, min_delivery_hours integer, sort_order numeric, param_json jsonb, copy_index integer, is_fixed_group text, is_pinned boolean, start_offset_in_seconds integer, next_start_offset_in_seconds integer, duration_in_seconds integer, nest_date date, orderline_count integer, product_amount numeric, part_amount integer, amount numeric, sqm numeric, forecast_sqm numeric, rework_count integer, rework_sqm numeric, impact_json jsonb, gross_sqm numeric, part_status_json jsonb, nest_ids bigint[], nest_count integer, seconds_to_logistics_date integer, class_names text[], unit_class_names text[])
	stable
	language plpgsql
as $$
#variable_conflict use_column
declare
    v_date date := (p_until at time zone current_setting('TimeZone'))::date;
    -- the open steps this board counts; a lookup later
    v_status_sequences constant integer[] := array[225, 290, 300, 350, 400, 450];
    -- print seconds per gross sqm at standard and at high speed; a lookup later
    v_standard_seconds_per_sqm constant numeric := 45;
    v_fast_seconds_per_sqm     constant numeric := 15;
    -- a lane item is never shorter than this, whatever the sqm say
    v_min_duration_in_seconds  constant integer := 900;
begin
    return query
    with base as (
        select b.material_id, b.material_name, b.production_line_id,
               b.tenant_id, b.tenant_name, b.resource_uid, b.resource_name,
               b.delivery_hours, b.min_delivery_hours, b.sort_order,
               b.param_json, b.copy_index, b.is_fixed_group, b.is_pinned,
               b.start_offset_in_seconds, b.next_start_offset_in_seconds
        -- only the materials whose interval (action.get_interval_dates on
        -- interval_start_date and interval_days) says the plan date is a
        -- production day; the rest of the plan stays out of the nest board
        from mock.get_print_schedule_materials(
                 p_until, p_step, p_line_type, p_tenant_ids, p_only_starting_today => true) b
    ),
    tenant as (
        select (v.value ->> 'tenant_id')::integer             as tenant_id,
               (v.value ->> 'production_company_id')::integer as production_company_id
        from relation.lookup lk
        cross join lateral jsonb_array_elements(lk.lookup_json) as v(value)
        where lk.lookup = 'lookup_tenants'
    ),
    the_plan as (
        -- the newest plan of this date, step and line type wins
        select plan_id
        from action.plan
        where plan_date = v_date and p_step = any (steps)
          and type = 'material-resource-plan'
          and (p_line_type is null or line_type = p_line_type)
        order by plan_id desc
        limit 1
    ),
    lane_nest as (
        -- the nests hung on the lane items of this lane, if any
        select l.sort_order, array_agg(distinct nli.nest_id) as nest_ids
        from the_plan tp
        join action.plan_lane l using (plan_id)
        join action.lane_item li on li.lane_id = l.lane_id
        join action.nest_lane_item nli on nli.lane_item_id = li.lane_item_id
        group by l.sort_order
    ),
    -- One aggregate call for all rows without lane nests, and one per distinct
    -- nest set for the rest, instead of one call per row: the detail behind
    -- the aggregate is the expensive part and it costs the same for one
    -- material as for fifty. Rows are matched back on material and line.
    window_agg as (
        select a.*
        from mapping.get_production_orderline_aggregate(
                 p_from             => p_until,
                 p_date_type        => 'nest',
                 p_look_back_days   => p_look_back_days,
                 p_look_ahead_days  => p_look_ahead_days,
                 -- empty, not null: null would mean every material
                 p_material_ids     => coalesce((select array_agg(distinct b.material_id)
                                                 from base b
                                                 left join lane_nest ln on ln.sort_order = b.sort_order
                                                 where b.material_id is not null and ln.nest_ids is null),
                                                '{}'::integer[]),
                 p_tenant_ids       => (select array_agg(distinct b.tenant_id) from base b),
                 p_status_sequences => v_status_sequences,
                 p_is_open          => true,
                 p_domain_id        => p_domain_id) a
    ),
    nest_agg as (
        -- the nests decide the scope here, no material filter needed; the
        -- aggregate has its own nest_ids column, so the set gets its own name
        select ns.nest_ids as lane_nest_ids, a.*
        from (select distinct ln.nest_ids from lane_nest ln) ns
        cross join lateral mapping.get_production_orderline_aggregate(
                 p_from             => p_until,
                 p_date_type        => 'nest',
                 p_nest_ids         => ns.nest_ids,
                 p_tenant_ids       => (select array_agg(distinct b.tenant_id) from base b),
                 p_status_sequences => v_status_sequences,
                 p_is_open          => true,
                 p_domain_id        => p_domain_id) a
    ),
    row_data as (
        select b.*, ln.nest_ids,
               o.orderline_count, o.product_amount, o.part_amount, o.amount,
               o.sqm, o.forecast_sqm, o.rework_count, o.rework_sqm, o.impact_json, o.gross_sqm,
               o.specs_json, o.part_status_json, o.seconds_to_logistics_date,
               o.class_names, o.unit_class_names
        from base b
        left join lane_nest ln on ln.sort_order = b.sort_order
        -- the longest delivery time this material has on the board
        left join lateral (
            select max(x.delivery_hours) as max_delivery_hours
            from base x
            where x.tenant_id = b.tenant_id and x.material_id = b.material_id
              and x.production_line_id = b.production_line_id
        ) lm on true
        -- the aggregate row of this material on this line and with the lane's
        -- delivery hours: from the nest set when the lane items carry nests,
        -- otherwise from the window call. A forecast-only row has no delivery
        -- hours and goes to the lane with the longest delivery time.
        left join lateral (
            select na.orderline_count, na.product_amount, na.part_amount, na.amount,
                   na.sqm, na.forecast_sqm, na.rework_count, na.rework_sqm, na.impact_json, na.gross_sqm,
                   na.specs_json, na.part_status_json, na.seconds_to_logistics_date,
                   na.class_names, na.unit_class_names
            from nest_agg na
            where ln.nest_ids is not null
              and na.lane_nest_ids = ln.nest_ids
              and na.material_id = b.material_id
              and na.production_line_id = b.production_line_id
              and (na.delivery_hours = b.delivery_hours
                   or (na.delivery_hours is null and b.delivery_hours = lm.max_delivery_hours))
            union all
            select wa.orderline_count, wa.product_amount, wa.part_amount, wa.amount,
                   wa.sqm, wa.forecast_sqm, wa.rework_count, wa.rework_sqm, wa.impact_json, wa.gross_sqm,
                   wa.specs_json, wa.part_status_json, wa.seconds_to_logistics_date,
                   wa.class_names, wa.unit_class_names
            from window_agg wa
            where ln.nest_ids is null
              and wa.material_id = b.material_id
              and wa.production_line_id = b.production_line_id
              and (wa.delivery_hours = b.delivery_hours
                   or (wa.delivery_hours is null and b.delivery_hours = lm.max_delivery_hours))
        ) o on true
    )
    select r.material_id, r.material_name, r.production_line_id,
           r.tenant_id, r.tenant_name, t.production_company_id, r.resource_uid, r.resource_name,
           r.delivery_hours, r.min_delivery_hours, r.sort_order,
           -- the sizes with what the gross sqm needs of each, and the print
           -- time of the row at both speeds
           jsonb_set(r.param_json, '{specs}', coalesce(r.specs_json, r.param_json -> 'specs'))
           || jsonb_build_object(
                  'standard_production_impact_in_seconds',
                      ceil(coalesce(r.gross_sqm, 0) * v_standard_seconds_per_sqm)::integer,
                  'fast_production_impact_in_seconds',
                      ceil(coalesce(r.gross_sqm, 0) * v_fast_seconds_per_sqm)::integer) as param_json,
           r.copy_index, r.is_fixed_group, r.is_pinned,
           r.start_offset_in_seconds, r.next_start_offset_in_seconds,
           -- noop rows keep their window duration; a material row gets its
           -- print time, but never less than the minimum
           case when r.material_id is null then r.next_start_offset_in_seconds
                else greatest(ceil(coalesce(r.gross_sqm, 0) * v_standard_seconds_per_sqm)::integer,
                              v_min_duration_in_seconds)
           end as duration_in_seconds,
           -- the day the row's orderlines nest: the plan date of the board
           v_date as nest_date,
           r.orderline_count, r.product_amount, r.part_amount, r.amount,
           r.sqm, r.forecast_sqm, r.rework_count, r.rework_sqm, r.impact_json, r.gross_sqm,
           coalesce(r.part_status_json, '[]'::jsonb),
           -- the nests of the lane items, not the ones the orderlines sit on
           coalesce(r.nest_ids, '{}'::bigint[]),
           coalesce(cardinality(r.nest_ids), 0),
           r.seconds_to_logistics_date,
           coalesce(r.class_names, '{}'::text[]),
           coalesce(r.unit_class_names, '{}'::text[])
    from row_data r
    left join tenant t on t.tenant_id = r.tenant_id
    order by r.tenant_id, r.sort_order;
end;
$$;

alter function mock.get_nest_schedule(timestamp with time zone, text, text, integer[], integer, integer, integer) owner to xfw3;

-- the board query is planned per call and inlines the aggregate; JIT compiling
-- it costs seconds and never pays back
alter function mock.get_nest_schedule(timestamp with time zone, text, text, integer[], integer, integer, integer) set jit = off;
