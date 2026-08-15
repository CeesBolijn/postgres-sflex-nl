-- return type changes, so the old signature has to go first
drop function if exists mock.get_nest_schedule(timestamp with time zone, text, text, integer[], boolean, integer, integer, integer);

create function mock.get_nest_schedule(p_until timestamp with time zone DEFAULT now(), p_step text DEFAULT 'print'::text, p_line_type text DEFAULT NULL::text, p_tenant_ids integer[] DEFAULT NULL::integer[], p_only_starting_today boolean DEFAULT false, p_look_back_days integer DEFAULT 0, p_look_ahead_days integer DEFAULT 0, p_domain_id integer DEFAULT 1) returns TABLE(material_id integer, material_name text, production_line_id integer, tenant_id integer, tenant_name text, production_company_id integer, resource_uid text, resource_name text, delivery_hours integer, min_delivery_hours integer, sort_order numeric, param_json jsonb, occurence integer, is_fixed_group text, is_pinned boolean, start_offset_in_seconds integer, next_start_offset_in_seconds integer, duration_in_seconds integer, orderline_count integer, product_amount numeric, part_amount integer, amount numeric, sqm numeric, forecast_sqm numeric, rework_count integer, rework_sqm numeric, gross_sqm numeric, part_status_json jsonb, nest_ids bigint[], nest_count integer, seconds_to_logistics_date integer, class_names text[], unit_class_names text[])
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
begin
    return query
    with base as (
        select b.material_id, b.material_name, b.production_line_id,
               b.tenant_id, b.tenant_name, b.resource_uid, b.resource_name,
               b.delivery_hours, b.min_delivery_hours, b.sort_order,
               b.param_json, b.occurence, b.is_fixed_group, b.is_pinned,
               b.start_offset_in_seconds, b.next_start_offset_in_seconds
        from mock.get_print_schedule_materials(
                 p_until, p_step, p_line_type, p_tenant_ids, p_only_starting_today) b
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
        where plan_date = v_date and step = p_step
          and type = 'material-resource-plan'
          and (p_line_type is null or line_type = p_line_type)
        order by plan_id desc
        limit 1
    ),
    lane_nest as (
        -- the nests hung on the lane items of this lane, if any
        select l.sort_order, array_agg(distinct nli.nest_id) as nest_ids
        from the_plan tp
        join action.lane l using (plan_id)
        join action.lane_item li on li.lane_id = l.lane_id
        join action.nest_lane_item nli on nli.lane_item_id = li.lane_item_id
        group by l.sort_order
    ),
    row_data as (
        select b.*, ln.nest_ids,
               o.orderline_count, o.product_amount, o.part_amount, o.amount,
               o.sqm, o.forecast_sqm, o.rework_count, o.rework_sqm, o.gross_sqm,
               o.specs_json, o.part_status_json, o.seconds_to_logistics_date,
               o.class_names, o.unit_class_names
        from base b
        left join lane_nest ln on ln.sort_order = b.sort_order
        -- the open orderlines of this material: on the nests when the lane
        -- items carry any, otherwise the ones nesting in the window (default
        -- today only); noop rows have no material and skip the call
        left join lateral (
            select a.orderline_count, a.product_amount, a.part_amount, a.amount,
                   a.sqm, a.forecast_sqm, a.rework_count, a.rework_sqm, a.gross_sqm,
                   a.specs_json, a.part_status_json, a.seconds_to_logistics_date,
                   a.class_names, a.unit_class_names
            from mapping.get_production_orderline_aggregate(
                     p_from               => p_until,
                     p_date_type          => 'nest',
                     p_look_back_days     => p_look_back_days,
                     p_look_ahead_days    => p_look_ahead_days,
                     p_nest_ids           => ln.nest_ids,
                     p_production_line_id => b.production_line_id,
                     p_material_ids       => array[b.material_id],
                     p_tenant_ids         => array[b.tenant_id],
                     p_status_sequences   => v_status_sequences,
                     p_is_open            => true,
                     p_domain_id          => p_domain_id) a
            where b.material_id is not null
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
           r.occurence, r.is_fixed_group, r.is_pinned,
           r.start_offset_in_seconds, r.next_start_offset_in_seconds,
           -- noop rows keep their window duration
           case when r.material_id is null then r.next_start_offset_in_seconds
                else ceil(coalesce(r.gross_sqm, 0) * v_standard_seconds_per_sqm)::integer
           end as duration_in_seconds,
           r.orderline_count, r.product_amount, r.part_amount, r.amount,
           r.sqm, r.forecast_sqm, r.rework_count, r.rework_sqm, r.gross_sqm,
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

alter function mock.get_nest_schedule(timestamp with time zone, text, text, integer[], boolean, integer, integer, integer) owner to xfw3;
