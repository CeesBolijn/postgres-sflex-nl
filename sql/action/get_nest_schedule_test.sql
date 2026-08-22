create function action.get_nest_schedule_test(p_until timestamp with time zone, p_line_type text, p_look_back integer DEFAULT '-1'::integer, p_look_ahead integer DEFAULT '-1'::integer, p_threshold numeric DEFAULT 10, p_tenant_ids integer[] DEFAULT NULL::integer[]) returns TABLE(board_date date, tenant_id integer, production_location text, count_production_locations integer, material_id integer, material_name text, production_line_id integer, interval_days integer, nest_moment_codes text[], material_icons jsonb, nest_time time with time zone, print_time time with time zone, start_offset_in_seconds integer, nest_plan_date date, unit_class_name text, imposition_grouping_key text[], imposition_i18n jsonb)
	stable
	language plpgsql
as $$
#variable_conflict use_column
DECLARE
    -- Temporary: tenant_id -> site name. Move to a lookup once there is one.
    v_tenant_name       jsonb := jsonb_build_object('1', 'Dokkum', '2', 'Bad Hersfeld');
    v_timeline_code     text := 'nest-time-scale';
    v_look_ahead_days   integer := 1;
    -- i18n per unit class, appended to material_icons per row.
    v_unit_i18n         jsonb := jsonb_build_object(
        'units-all', jsonb_build_object(
            'de', jsonb_build_object('title', 'Alle'),
            'en', jsonb_build_object('title', 'All'),
            'es', jsonb_build_object('title', 'Todos'),
            'fr', jsonb_build_object('title', 'Tous'),
            'nl', jsonb_build_object('title', 'Alles'),
            'uk', jsonb_build_object('title', 'Усе')),
        'units-lte-threshold', jsonb_build_object(
            'de', jsonb_build_object('title', 'Kleine Auflage'),
            'en', jsonb_build_object('title', 'Small run'),
            'es', jsonb_build_object('title', 'Tirada pequeña'),
            'fr', jsonb_build_object('title', 'Petit tirage'),
            'nl', jsonb_build_object('title', 'Kleine oplage'),
            'uk', jsonb_build_object('title', 'Малий наклад')),
        'units-gt-threshold', jsonb_build_object(
            'de', jsonb_build_object('title', 'Große Auflage'),
            'en', jsonb_build_object('title', 'Large run'),
            'es', jsonb_build_object('title', 'Tirada grande'),
            'fr', jsonb_build_object('title', 'Grand tirage'),
            'nl', jsonb_build_object('title', 'Grote oplage'),
            'uk', jsonb_build_object('title', 'Великий наклад')));
    v_board_date        date;
BEGIN
    -- First same-or-next working day, straight from the calendar table
    -- (the same source get_interval_dates sequences internally).
    SELECT min(d.date)
      INTO v_board_date
      FROM action.dates d
     WHERE d.date >= (p_until AT TIME ZONE 'UTC')::date
       AND d.is_weekend = false
       AND NOT (coalesce(p_tenant_ids, d.tenants_mandatory_day_off) <@ d.tenants_mandatory_day_off and d.tenants_mandatory_day_off <> '{}');

    RETURN QUERY
    -- The timeline segments, fetched with the SAME parameters the
    -- time_scale_config passes on the front-end, so both sides see the
    -- same window (-1 = unbounded). start_offset_in_seconds is relative
    -- to the FIRST segment of that window, so a row can only land in a
    -- column by carrying the segment's own offset -- matching, not
    -- deriving. MATERIALIZED: the function is VOLATILE.
    WITH cte_segment AS MATERIALIZED (
        SELECT
            (s.start_at AT TIME ZONE 'UTC')::date                        AS segment_date,
            EXTRACT(EPOCH FROM (s.start_at AT TIME ZONE 'UTC')::time)::integer AS segment_time_offset,
            s.start_offset_in_seconds
        FROM production.get_timeline_view_segments(
                 p_code       => v_timeline_code,
                 p_until      => p_until,
                 p_look_back  => p_look_back,
                 p_look_ahead => p_look_ahead) s
    ),

    -- The board's schedule rows for the day.
    cte_schedule AS (
        SELECT
            pl.tenant_id,
            mps.material_id,
            mps.material_name,
            mps.production_line_id,
            mps.nest_moment_codes,
            mps.interval_days
        FROM mock.material_print_schedule mps
        JOIN relation.production_line pl
          ON pl.line_id = mps.production_line_id
         AND pl.line_type = p_line_type
        JOIN action.get_interval_dates(mps.interval_start_date, v_board_date, mps.interval_days, v_look_ahead_days) gid
          ON gid.interval_date = v_board_date
    ),

    -- Schedule rows exploded to one row per nest moment, each resolved to
    -- its segment on the board date by time-of-day. LEFT twice: a material
    -- with unknown codes keeps a row with null offsets, and a moment whose
    -- time has no segment in the window stays visible rather than vanishing.
    cte_moment AS (
        SELECT
            s.*,
            (nm.value -> 'nest_time'  ->> 'time')::timetz  AS nest_time,
            (nm.value -> 'print_time' ->> 'time')::timetz  AS print_time,
            seg.start_offset_in_seconds
        FROM cte_schedule s
        LEFT JOIN LATERAL jsonb_array_elements(action.get_nest_moments(s.nest_moment_codes)) AS nm(value) ON true
        LEFT JOIN cte_segment seg
               ON seg.segment_date = v_board_date
              AND seg.segment_time_offset =
                  EXTRACT(EPOCH FROM (nm.value -> 'nest_time' ->> 'time')::timetz)::integer
    ),

    -- How many sites a material nests on AT THIS MOMENT; the front-end
    -- hides the location level when this is 1.
    cte_location_count AS (
        SELECT
            m.material_id, m.start_offset_in_seconds,
            count(DISTINCT m.tenant_id)::integer AS count_production_locations
        FROM cte_moment m
        GROUP BY m.material_id, m.start_offset_in_seconds
    ),

    -- Imposition groups per material, via the unit manifest aggregate over
    -- the open orderlines. MATERIALIZED: one scan, then a cheap join per
    -- row. The array_agg subquery feeds the aggregate function the full
    -- orderline set in a single call.
    cte_imposition AS MATERIALIZED (
        SELECT DISTINCT
            cs.material_id,
            agg.option_codes AS imposition_grouping_key,
            agg.i18n         AS imposition_i18n
        FROM mapping.component_specs cs
        JOIN mapping.get_unit_manifest_aggregate(
                 (SELECT array_agg(DISTINCT x.production_orderline_id)
                  FROM mapping.component_specs x
                  WHERE x.is_open = true),
                 'imposition'
             ) AS agg
          ON agg.production_orderline_id = cs.production_orderline_id
        WHERE cs.is_open = true
          AND agg.option_codes IS NOT NULL
          AND EXISTS (SELECT 1 FROM unnest(agg.option_codes) u(code)
                      WHERE u.code ~ '(^|;)material\.')
          AND EXISTS (SELECT 1 FROM unnest(agg.option_codes) u(code)
                      WHERE u.code ~ '(^|;)print-method\.')
    )

    -- One row per material x moment x nest plan date x unit group x
    -- imposition group. Plan dates run up to the material's next
    -- production day: a daily material plans today and tomorrow, a
    -- multi-day material its full interval.
    SELECT
        v_board_date,
        m.tenant_id::integer,
        coalesce(v_tenant_name ->> m.tenant_id::text,
                 'tenant-' || m.tenant_id)::text                     AS production_location,
        lc.count_production_locations,
        m.material_id::integer,
        m.material_name::text,
        m.production_line_id::integer,
        m.interval_days::integer,
        m.nest_moment_codes::text[],
        -- Icon objects for the material row: the print agenda marker for
        -- non-daily materials, plus the unit-group icon for this row.
        ((CASE WHEN m.interval_days > 1
               THEN jsonb_build_array(jsonb_build_object(
                        'class_name', 'print_schedule',
                        'i18n', jsonb_build_object(
                            'de', jsonb_build_object('title', 'Druckagenda'),
                            'en', jsonb_build_object('title', 'Print agenda'),
                            'es', jsonb_build_object('title', 'Agenda de impresión'),
                            'fr', jsonb_build_object('title', 'Agenda d''impression'),
                            'nl', jsonb_build_object('title', 'Print agenda'),
                            'uk', jsonb_build_object('title', 'Графік друку'))))
               ELSE '[]'::jsonb
          END)
          || jsonb_build_array(jsonb_build_object(
                 'class_name', u.unit_class_name,
                 'i18n', v_unit_i18n -> u.unit_class_name)))         AS material_icons,
        m.nest_time,
        m.print_time,
        m.start_offset_in_seconds,
        pd.interval_date                                             AS nest_plan_date,
        u.unit_class_name::text,
        im.imposition_grouping_key,
        im.imposition_i18n
    FROM cte_moment m
    JOIN cte_location_count lc
      ON lc.material_id = m.material_id
     AND lc.start_offset_in_seconds IS NOT DISTINCT FROM m.start_offset_in_seconds
    -- LEFT so a moment keeps its row even if the calendar yields nothing.
    -- WITH ORDINALITY numbers the plan dates; since get_interval_dates
    -- yields working days in order, ordinality 1 and 2 are the board day
    -- and the next WORKING day -- a Friday board splits from Tuesday, not
    -- from Sunday.
    LEFT JOIN LATERAL action.get_interval_dates(
                  v_board_date, v_board_date, 1,
                  CASE WHEN m.interval_days = 1 THEN 2 ELSE m.interval_days END)
              WITH ORDINALITY AS pd(interval_date, plan_day_rank) ON true
    -- Unit groups per plan date: the first two working days nest
    -- everything as one; beyond that the work splits on p_threshold (the
    -- threshold is applied when orders attach; the split is structural).
    CROSS JOIN LATERAL unnest(
        CASE WHEN pd.plan_day_rank <= 2
             THEN ARRAY['units-all']
             ELSE ARRAY['units-lte-threshold', 'units-gt-threshold']
        END) AS u(unit_class_name)
    -- LEFT so a material without imposition groups stays visible.
    LEFT JOIN cte_imposition im
           ON im.material_id = m.material_id
    ORDER BY
        m.start_offset_in_seconds,
        m.material_name,
        m.tenant_id,
        pd.interval_date,
        u.unit_class_name DESC,
        im.imposition_grouping_key;
END;
$$;

alter function action.get_nest_schedule_test(timestamp with time zone, text, integer, integer, numeric, integer[]) owner to xfw3;

