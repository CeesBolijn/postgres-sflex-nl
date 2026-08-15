create function get_nest_schedule(p_until timestamp with time zone DEFAULT now(), p_step text DEFAULT 'print'::text, p_line_type text DEFAULT NULL::text, p_tenant_ids integer[] DEFAULT NULL::integer[], p_only_starting_today boolean DEFAULT false) returns TABLE(material_id integer, material_name text, production_line_id integer, tenant_id integer, tenant_name text, resource_uid text, resource_name text, delivery_hours integer, min_delivery_hours integer, sort_order numeric, param_json jsonb, occurence integer, is_fixed_group text, is_pinned boolean, start_offset_in_seconds integer, actual_sqm numeric, forecast_sqm numeric, sqm numeric, next_start_offset_in_seconds integer, duration_in_seconds integer)
	stable
	language plpgsql
as $$
#variable_conflict use_column
DECLARE
    v_date date;
    -- board default, same base as the print schedule impacts
    v_seconds_per_sqm constant numeric := 45;
BEGIN
    v_date := (p_until AT TIME ZONE current_setting('TimeZone'))::date;

    RETURN QUERY
    WITH base AS (
        SELECT b.material_id, b.material_name, b.production_line_id,
               b.tenant_id, b.tenant_name, b.resource_uid, b.resource_name,
               b.delivery_hours, b.min_delivery_hours, b.sort_order,
               b.param_json, b.occurence, b.is_fixed_group, b.is_pinned,
               b.start_offset_in_seconds, b.next_start_offset_in_seconds
        FROM mock.get_print_schedule_materials(
                 p_until, p_step, p_line_type, p_tenant_ids, p_only_starting_today) b
    ),
    tenant AS (
        SELECT (v.value ->> 'tenant_id')::integer             AS tenant_id,
               (v.value ->> 'production_company_id')::integer AS production_company_id
        FROM relation.lookup lk
        CROSS JOIN LATERAL jsonb_array_elements(lk.lookup_json) AS v(value)
        WHERE lk.lookup = 'lookup_tenants'
    ),
    mat AS (
        -- one entry per material row with its interval days
        SELECT DISTINCT b.tenant_id, b.material_id, b.production_line_id,
               coalesce(nullif(mps.interval_days, 0), 1) AS interval_days
        FROM base b
        JOIN mock.material_print_schedule mps
             ON mps.material_id = b.material_id
            AND mps.production_line_id = b.production_line_id
            AND mps.tenant_id = b.tenant_id
        WHERE b.material_id IS NOT NULL
    ),
    workday AS (
        -- workday 1 is the plan date itself
        SELECT d.date, (row_number() OVER (ORDER BY d.date))::integer AS day_index
        FROM action.dates d
        WHERE d.date >= v_date AND d.is_weekend = false AND d.is_mandatory_day_off = false
        ORDER BY d.date
        LIMIT (SELECT max(interval_days) FROM mat)
    ),
    material_sqm AS (
        -- one sum per material over its interval days: forecast for day 1 and
        -- 2, actual inflow beyond that
        SELECT mt.tenant_id, mt.material_id, mt.production_line_id,
               sum(f.actual_sqm)   AS actual_sqm,
               sum(f.forecast_sqm) AS forecast_sqm,
               sum(CASE WHEN w.day_index <= 2 THEN f.forecast_sqm ELSE f.actual_sqm END) AS sqm
        FROM mat mt
        JOIN tenant t ON t.tenant_id = mt.tenant_id
        JOIN workday w ON w.day_index <= mt.interval_days
        LEFT JOIN mock.get_production_forecast_material(
                      v_date,
                      (SELECT (max(w2.date) - v_date + 1)::integer FROM workday w2),
                      p_line_type) f
               ON f.production_company_id = t.production_company_id
              AND f.material_id = mt.material_id
              AND f.date = w.date
        GROUP BY mt.tenant_id, mt.material_id, mt.production_line_id
    )
    SELECT b.material_id, b.material_name, b.production_line_id,
           b.tenant_id, b.tenant_name, b.resource_uid, b.resource_name,
           b.delivery_hours, b.min_delivery_hours, b.sort_order,
           b.param_json, b.occurence, b.is_fixed_group, b.is_pinned,
           b.start_offset_in_seconds,
           coalesce(s.actual_sqm, 0)   AS actual_sqm,
           coalesce(s.forecast_sqm, 0) AS forecast_sqm,
           coalesce(s.sqm, 0)          AS sqm,
           b.next_start_offset_in_seconds,
           ceil(coalesce(s.sqm, 0) * v_seconds_per_sqm
              / coalesce((
                    SELECT (v.value ->> 'speed_factor')::numeric
                    FROM jsonb_array_elements(coalesce(mps.valid_resources_json, '[]'::jsonb)) AS v(value)
                    WHERE v.value ->> 'resource_uid' = b.resource_uid
                    LIMIT 1
                ), 1))::int AS duration_in_seconds
    FROM base b
    LEFT JOIN mock.material_print_schedule mps
           ON mps.material_id = b.material_id
          AND mps.production_line_id = b.production_line_id
          AND mps.tenant_id = b.tenant_id
    LEFT JOIN material_sqm s
           ON s.tenant_id = b.tenant_id
          AND s.material_id = b.material_id
          AND s.production_line_id = b.production_line_id
    ORDER BY b.tenant_id, b.sort_order;
END;
$$;

alter function get_nest_schedule(timestamp with time zone, text, text, integer[], boolean) owner to xfw3;

create function get_nest_schedule(p_until timestamp with time zone DEFAULT now(), p_step text DEFAULT 'print'::text, p_line_type text DEFAULT NULL::text, p_tenant_ids integer[] DEFAULT NULL::integer[], p_only_starting_today boolean DEFAULT false, p_look_back_days integer DEFAULT 0, p_look_ahead_days integer DEFAULT 0, p_domain_id integer DEFAULT 1) returns TABLE(material_id integer, material_name text, production_line_id integer, tenant_id integer, tenant_name text, resource_uid text, resource_name text, delivery_hours integer, min_delivery_hours integer, sort_order numeric, param_json jsonb, occurence integer, is_fixed_group text, is_pinned boolean, start_offset_in_seconds integer, next_start_offset_in_seconds integer, duration_in_seconds integer, orderline_count integer, product_amount numeric, sqm numeric, rework_count integer, rework_sqm numeric, gross_sqm numeric, part_amount integer, status_json jsonb, part_status_json jsonb, nest_ids bigint[], nest_count integer, seconds_to_logistics_date integer, class_names text[], unit_class_names text[])
	stable
	language plpgsql
as $$
#variable_conflict use_column
declare
    v_date date;
    -- the open steps this board counts
    v_status_sequences constant integer[] := array[225, 290, 300, 350, 400, 450];
    -- temporary, until the formulas and factors come from the lookup
    v_params constant jsonb := jsonb_build_object(
        'waste_perc', 0.15,
        'standard_speed_print_time_sqm_in_seconds', 45,
        'high_speed_print_time_sqm_in_seconds', 15);
    -- width and height are in cm; the impacts follow the real sqm of the open
    -- orderlines, so they are the same for every panel size
    v_formula constant jsonb := jsonb_build_array(
        'panel_area_m2 = width * height / 10000',
        'net_area_m2 = panel_area_m2 * (1 - waste_perc)',
        'actual_panels = sqm / net_area_m2',
        'gross_sqm = sqm / (1 - waste_perc)',
        'standard_production_impact_in_seconds = gross_sqm * standard_speed_print_time_sqm_in_seconds',
        'fast_production_impact_in_seconds = gross_sqm * high_speed_print_time_sqm_in_seconds');
begin
    v_date := (p_until at time zone current_setting('TimeZone'))::date;

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
        -- the nests of this lane, if its lane items have any
        select l.sort_order, array_agg(distinct nli.nest_id) as nest_ids
        from the_plan tp
        join action.lane l using (plan_id)
        join action.lane_item li on li.lane_id = l.lane_id
        join action.nest_lane_item nli on nli.lane_item_id = li.lane_item_id
        group by l.sort_order
    ),
    row_data as (
        select b.*, o.material_media_type_id, o.orderline_count, o.product_amount,
               o.sqm, o.rework_count, o.rework_sqm, o.part_amount,
               o.status_json, o.part_status_json, o.nest_ids, o.nest_count,
               o.seconds_to_logistics_date, o.class_names, o.unit_class_names
        from base b
        left join lane_nest ln on ln.sort_order = b.sort_order
        -- the open orderlines of this material: by nest when the lane items
        -- carry nests, otherwise over the date window of the board
        left join lateral (
            select a.material_media_type_id, a.orderline_count, a.product_amount, a.sqm,
                   a.rework_count, a.rework_sqm, a.part_amount,
                   a.status_json, a.part_status_json, a.nest_ids, a.nest_count,
                   a.seconds_to_logistics_date, a.class_names, a.unit_class_names
            from mapping.get_production_orderline_aggregate(
                     p_from               => p_until,
                     p_nest_ids           => ln.nest_ids,
                     p_production_line_id => b.production_line_id,
                     p_material_ids       => array[b.material_id],
                     p_status_sequences   => v_status_sequences,
                     p_is_open            => true,
                     p_domain_id          => p_domain_id) a
            where ln.nest_ids is not null
            union all
            select a.material_media_type_id, a.orderline_count, a.product_amount, a.sqm,
                   a.rework_count, a.rework_sqm, a.part_amount,
                   a.status_json, a.part_status_json, a.nest_ids, a.nest_count,
                   a.seconds_to_logistics_date, a.class_names, a.unit_class_names
            from mapping.get_production_orderline_aggregate(
                     p_from               => p_until,
                     p_look_back_days     => p_look_back_days,
                     p_look_ahead_days    => p_look_ahead_days,
                     p_production_line_id => b.production_line_id,
                     p_material_ids       => array[b.material_id],
                     p_status_sequences   => v_status_sequences,
                     p_is_open            => true,
                     p_domain_id          => p_domain_id) a
            where ln.nest_ids is null and b.material_id is not null
        ) o on true
    ),
    spec as (
        -- one row per size: the formulas turn the real sqm into panels and
        -- into the print time of this row
        select r.sort_order, r.tenant_id, spec.ord,
               spec.value || jsonb_build_object(
                   'actual_panels', ceil((f.result ->> 'actual_panels')::numeric)) as spec_json,
               ceil((f.result ->> 'standard_production_impact_in_seconds')::numeric)::integer
                   as standard_production_impact_in_seconds,
               ceil((f.result ->> 'fast_production_impact_in_seconds')::numeric)::integer
                   as fast_production_impact_in_seconds,
               (f.result ->> 'gross_sqm')::numeric as gross_sqm
        from row_data r
        cross join lateral jsonb_array_elements(r.param_json -> 'specs')
             with ordinality as spec(value, ord)
        cross join lateral (
            select evaluate_many_nas(v_formula,
                       v_params
                       || jsonb_build_object('sqm', coalesce(r.sqm, 0) + coalesce(r.rework_sqm, 0))
                       || jsonb_build_object('width',  spec.value -> 'width',
                                             'height', spec.value -> 'height')) as result
        ) f
    ),
    spec_agg as (
        -- the sizes back into one json, and the slowest print time as the
        -- width of the lane item
        select sp.sort_order, sp.tenant_id,
               jsonb_agg(sp.spec_json order by sp.ord)       as specs,
               max(sp.standard_production_impact_in_seconds) as standard_production_impact_in_seconds,
               min(sp.fast_production_impact_in_seconds)     as fast_production_impact_in_seconds,
               max(sp.gross_sqm)                             as gross_sqm
        from spec sp
        group by sp.sort_order, sp.tenant_id
    )
    select r.material_id, r.material_name, r.production_line_id,
           r.tenant_id, r.tenant_name, r.resource_uid, r.resource_name,
           r.delivery_hours, r.min_delivery_hours, r.sort_order,
           jsonb_set(r.param_json, '{specs}',
                     coalesce(sa.specs, r.param_json -> 'specs'))
           || jsonb_build_object(
                  'standard_production_impact_in_seconds', sa.standard_production_impact_in_seconds,
                  'fast_production_impact_in_seconds',     sa.fast_production_impact_in_seconds) as param_json,
           r.occurence, r.is_fixed_group, r.is_pinned,
           r.start_offset_in_seconds, r.next_start_offset_in_seconds,
           -- noop rows keep their window duration
           case when r.material_id is null then r.next_start_offset_in_seconds
                else sa.standard_production_impact_in_seconds end as duration_in_seconds,
           r.orderline_count, r.product_amount, r.sqm, r.rework_count, r.rework_sqm,
           sa.gross_sqm, r.part_amount,
           coalesce(r.status_json, '[]'::jsonb),
           coalesce(r.part_status_json, '[]'::jsonb),
           coalesce(r.nest_ids, '{}'::bigint[]), coalesce(r.nest_count, 0),
           r.seconds_to_logistics_date,
           coalesce(r.class_names, '{}'::text[]),
           coalesce(r.unit_class_names, '{}'::text[])
    from row_data r
    left join spec_agg sa on sa.sort_order is not distinct from r.sort_order
                         and sa.tenant_id  is not distinct from r.tenant_id
    order by r.tenant_id, r.sort_order;
end;
$$;

alter function get_nest_schedule(timestamp with time zone, text, text, integer[], boolean, integer, integer, integer) owner to xfw3;

