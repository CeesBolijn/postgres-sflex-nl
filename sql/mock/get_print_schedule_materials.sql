-- return type changes (occurence -> copy_index), so the old signature has to go first
drop function if exists mock.get_print_schedule_materials(timestamp with time zone, text, text, integer[], boolean);

create function mock.get_print_schedule_materials(p_until timestamp with time zone DEFAULT now(), p_step text DEFAULT 'print'::text, p_line_type text DEFAULT NULL::text, p_tenant_ids integer[] DEFAULT NULL::integer[], p_only_starting_today boolean DEFAULT false) returns TABLE(material_id integer, material_name text, production_line_id integer, tenant_id integer, tenant_name text, resource_uid text, resource_name text, delivery_hours integer, min_delivery_hours integer, sort_order numeric, param_json jsonb, copy_index integer, is_fixed_group text, is_pinned boolean, start_offset_in_seconds integer, next_start_offset_in_seconds integer)
	stable
	language plpgsql
as $$
#variable_conflict use_column
DECLARE
    v_date  date;
    v_fixed jsonb;
BEGIN
    v_date := (p_until AT TIME ZONE current_setting('TimeZone'))::date;

    -- fixed groups from the lookup: code (= delivery hours) to the group and
    -- the nest time start offset
    SELECT coalesce(jsonb_object_agg(
               v.value ->> 'code',
               jsonb_build_object(
                   'group',  v.value ->> 'is_fixed_group',
                   'offset', v.value #> '{nest_moments,0,nest_time,start_offset_in_seconds}')),
           '{}'::jsonb)
    INTO v_fixed
    FROM production.lookup l
    CROSS JOIN LATERAL jsonb_array_elements(l.lookup_json) AS v(value)
    WHERE l.lookup = 'lookup_nest_moments'
      AND v.value ->> 'is_fixed_group' IS NOT NULL
      AND v.value #>> '{nest_moments,0,nest_time,start_offset_in_seconds}' IS NOT NULL;

    RETURN QUERY
    WITH the_plan AS (
        -- the newest plan of this date, step and line type wins
        SELECT plan_id
        FROM action.plan
        WHERE plan_date = v_date AND p_step = ANY (steps)
          AND type = 'material-resource-plan'
          AND (p_line_type IS NULL OR line_type = p_line_type)
        ORDER BY plan_id DESC
        LIMIT 1
    ),
    tenant AS (
        SELECT (v.value ->> 'tenant_id')::integer AS tenant_id,
               v.value ->> 'name'                 AS tenant_name
        FROM relation.lookup lk
        CROSS JOIN LATERAL jsonb_array_elements(lk.lookup_json) AS v(value)
        WHERE lk.lookup = 'lookup_tenants'
    ),
    material_row AS (
        SELECT m.material_id, mps.material_name, m.production_line_id,
               m.tenant_id, t.tenant_name, m.resource_uid, r.resource_name,
               mps.delivery_hours, mps.min_delivery_hours, l.sort_order,
               -- only the two keys the tooltip reads
               jsonb_build_object('specs', coalesce((
                   SELECT jsonb_agg(jsonb_build_object('width',  spec.value -> 'width',
                                                       'height', spec.value -> 'height')
                                    ORDER BY spec.ord)
                   FROM jsonb_array_elements(coalesce(mpl.line_json -> 'specs', '[]'::jsonb))
                        WITH ORDINALITY AS spec(value, ord)
               ), '[]'::jsonb)) AS param_json,
               m.copy_index,
               v_fixed -> mps.delivery_hours::text ->> 'group' AS is_fixed_group,
               m.is_pinned,
               -- fixed rows take the lookup moment, the rest their pinned time
               CASE WHEN v_fixed ? mps.delivery_hours::text
                    THEN (v_fixed -> mps.delivery_hours::text ->> 'offset')::integer
                    ELSE m.start_offset_in_seconds
               END AS start_offset_in_seconds,
               m.next_start_offset_in_seconds
        FROM the_plan tp
        JOIN action.plan_lane l USING (plan_id)
        JOIN mock.material_resource_plan_lane mrpl ON mrpl.lane_id = l.lane_id
        JOIN mock.material_resource_plan m
             ON m.material_resource_plan_id = mrpl.material_resource_plan_id
        LEFT JOIN relation.resource r ON r.resource_uid = m.resource_uid
        LEFT JOIN mock.material_print_schedule mps
               ON mps.material_id = m.material_id
              AND mps.production_line_id = m.production_line_id
              AND mps.tenant_id = m.tenant_id
        LEFT JOIN mapping.material_production_line mpl
               ON mpl.material_id = m.material_id
              AND mpl.production_line_id = m.production_line_id
        LEFT JOIN tenant t ON t.tenant_id = m.tenant_id
        WHERE (p_tenant_ids IS NULL OR m.tenant_id = ANY (p_tenant_ids))
          -- only materials whose interval says the plan date is a production day
          AND (NOT p_only_starting_today OR EXISTS (
                   SELECT 1
                   FROM action.get_interval_dates(
                            (SELECT min(d.date)
                             FROM action.dates d
                             WHERE d.date >= coalesce(mps.interval_start_date, v_date)
                               AND d.is_weekend = false
                               AND NOT (coalesce(p_tenant_ids, d.tenants_mandatory_day_off) <@ d.tenants_mandatory_day_off and d.tenants_mandatory_day_off <> '{}')),
                            v_date,
                            coalesce(nullif(mps.interval_days, 0), 1),
                            1, false, false, 0) AS i(interval_date)
                   WHERE i.interval_date = v_date))
    )
    SELECT * FROM material_row
    UNION ALL
    -- one row per tenant noop window, newest per slot; removed time the client
    -- lays the timeline around (column names and types come from the first branch)
    SELECT NULL, NULL, NULL, s.tenant_id, t.tenant_name, NULL, NULL, NULL, NULL, NULL,
           jsonb_build_object('specs', '[]'::jsonb), NULL, 'noop', false,
           s.start_offset_in_seconds, s.duration_in_seconds
    FROM (
        SELECT DISTINCT ON (n.rule_path, n.weekday, n.start_offset_in_seconds)
               n.rule_path::integer AS tenant_id,
               n.start_offset_in_seconds, n.duration_in_seconds
        FROM action.non_working_times n
        WHERE n.type = 'noop'
          AND n.rule_path NOT LIKE '%.%'
          AND n.rule_path IN (SELECT DISTINCT mr.tenant_id::text FROM material_row mr)
          AND (n.weekday IS NULL OR n.weekday = extract(dow FROM v_date)::smallint + 1)
        ORDER BY n.rule_path, n.weekday, n.start_offset_in_seconds,
                 n.non_working_time_id DESC
    ) s
    LEFT JOIN tenant t ON t.tenant_id = s.tenant_id
    WHERE s.duration_in_seconds > 0
    ORDER BY tenant_id, sort_order;
END;
$$;

alter function mock.get_print_schedule_materials(timestamp with time zone, text, text, integer[], boolean) owner to xfw3;

