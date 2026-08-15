create function get_nest_schedule(p_until timestamp with time zone, p_line_type text, p_look_back integer DEFAULT '-1'::integer, p_look_ahead integer DEFAULT '-1'::integer) returns TABLE(board_date date, tenant_id integer, production_location text, count_production_locations integer, material_id integer, material_name text, production_line_id integer, interval_days integer, nest_moment_codes text[], nest_moment_code text, day_offset integer, material_icons jsonb, nest_time time with time zone, print_time time with time zone, start_offset_in_seconds integer, nest_plan_date date, occurence integer, imposition_grouping_key text[], imposition_i18n jsonb)
	stable
	language plpgsql
as $$
#variable_conflict use_column
DECLARE
    -- Temporary: tenant_id -> site name. Move to a lookup once there is one.
    v_tenant_name        jsonb   := jsonb_build_object('1', 'Dokkum', '2', 'Bad Hersfeld');
    v_timeline_code      text    := 'nest-time-scale';
    v_nest_moment_lookup text    := 'lookup_nest_moments';
    v_look_ahead_days    integer := 1;
    v_board_date         date;
    v_max_day_offset     integer;
BEGIN
    -- First same-or-next working day, straight from the calendar table
    -- (the same source get_interval_dates sequences internally).
    SELECT min(d.date)
      INTO v_board_date
      FROM action.dates d
     WHERE d.date >= (p_until AT TIME ZONE 'UTC')::date
       AND d.is_weekend = false
       AND d.is_mandatory_day_off IS NOT TRUE;

    IF v_board_date IS NULL THEN
        RETURN;
    END IF;

    -- The furthest a nest moment reaches, so the working day sequence below is
    -- long enough to resolve every offset the lookup can produce.
    SELECT coalesce(max((c.value ->> 'day_offset')::integer), 0)
      INTO v_max_day_offset
      FROM production.lookup l
      CROSS JOIN LATERAL jsonb_array_elements(l.lookup_json) AS c(value)
     WHERE l.lookup = v_nest_moment_lookup;

    RETURN QUERY
    -- The timeline segments, fetched with the SAME parameters the
    -- time_scale_config passes on the front-end, so both sides see the
    -- same window (-1 = unbounded). start_offset_in_seconds is relative
    -- to the FIRST segment of that window, so a row can only land in a
    -- column by carrying the segment's own offset -- matching, not
    -- deriving. MATERIALIZED: the function is VOLATILE.
    WITH cte_segment AS MATERIALIZED (
        SELECT
            (s.start_at AT TIME ZONE 'UTC')::date                              AS segment_date,
            EXTRACT(EPOCH FROM (s.start_at AT TIME ZONE 'UTC')::time)::integer AS segment_time_offset,
            s.start_offset_in_seconds
        FROM production.get_timeline_view_segments(
                 p_code       => v_timeline_code,
                 p_until      => p_until,
                 p_look_back  => p_look_back,
                 p_look_ahead => p_look_ahead) s
    ),

    -- The board's schedule rows for the day. interval_days decides WHICH
    -- materials run today, it no longer fans out the plan dates.
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

    -- day_index 0 is the board date itself; weekends and days off are skipped,
    -- so a day_offset counts working days, the same way the print schedule
    -- moves a production day forward.
    cte_workday AS (
        SELECT d.date,
               (row_number() OVER (ORDER BY d.date) - 1)::integer AS day_index
        FROM action.dates d
        WHERE d.date >= v_board_date
          AND d.is_weekend = false
          AND d.is_mandatory_day_off IS NOT TRUE
        ORDER BY d.date
        LIMIT v_max_day_offset + 1
    ),

    -- One row per nest moment CODE, not per distinct moment: the day_offset
    -- lives on the code, and several codes share the same time of day. Two
    -- codes with the same offset must stay two rows, so nothing is
    -- deduplicated here. Each row is resolved to its segment on the board date
    -- by time of day. LEFT twice: a material whose codes are unknown to the
    -- lookup keeps a row with null offsets, and a moment whose time has no
    -- segment in the window stays visible rather than vanishing.
    cte_moment AS (
        SELECT
            s.*,
            m.nest_moment_code,
            m.day_offset,
            m.nest_time,
            m.print_time,
            seg.start_offset_in_seconds
        FROM cte_schedule s
        LEFT JOIN LATERAL (
            SELECT
                c.value ->> 'code'                              AS nest_moment_code,
                coalesce((c.value ->> 'day_offset')::integer, 0) AS day_offset,
                (nm.value -> 'nest_time'  ->> 'time')::timetz    AS nest_time,
                (nm.value -> 'print_time' ->> 'time')::timetz    AS print_time
            FROM production.lookup l
            CROSS JOIN LATERAL jsonb_array_elements(l.lookup_json) AS c(value)
            CROSS JOIN LATERAL jsonb_array_elements(c.value -> 'nest_moments') AS nm(value)
            WHERE l.lookup = v_nest_moment_lookup
              AND c.value ->> 'code' = ANY (s.nest_moment_codes)
        ) m ON true
        LEFT JOIN cte_segment seg
               ON seg.segment_date = v_board_date
              AND seg.segment_time_offset = EXTRACT(EPOCH FROM m.nest_time)::integer
    ),

    -- The plan date is the working day day_offset days after the board date.
    -- Codes that share an offset land on the same date, so occurence numbers
    -- the repeats: the board groups on the date and would otherwise collapse
    -- them into one card.
    cte_row AS (
        SELECT
            m.*,
            w.date AS nest_plan_date,
            row_number() OVER (
                PARTITION BY m.tenant_id, m.material_id, m.production_line_id,
                             m.start_offset_in_seconds, w.date
                ORDER BY m.nest_moment_code)::integer AS occurence
        FROM cte_moment m
        LEFT JOIN cte_workday w ON w.day_index = m.day_offset
    ),

    -- How many sites a material nests on AT THIS MOMENT; the front-end
    -- hides the location level when this is 1.
    cte_location_count AS (
        SELECT
            r.material_id, r.start_offset_in_seconds,
            count(DISTINCT r.tenant_id)::integer AS count_production_locations
        FROM cte_row r
        GROUP BY r.material_id, r.start_offset_in_seconds
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

    -- One row per material x nest moment code x imposition group.
    SELECT
        v_board_date,
        r.tenant_id::integer,
        coalesce(v_tenant_name ->> r.tenant_id::text,
                 'tenant-' || r.tenant_id)::text                     AS production_location,
        lc.count_production_locations,
        r.material_id::integer,
        r.material_name::text,
        r.production_line_id::integer,
        r.interval_days::integer,
        r.nest_moment_codes::text[],
        r.nest_moment_code::text,
        r.day_offset::integer,
        -- Icon objects for the material row: the print agenda marker for
        -- non-daily materials.
        (CASE WHEN r.interval_days > 1
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
         END)                                                        AS material_icons,
        r.nest_time,
        r.print_time,
        r.start_offset_in_seconds,
        r.nest_plan_date,
        r.occurence,
        im.imposition_grouping_key,
        im.imposition_i18n
    FROM cte_row r
    JOIN cte_location_count lc
      ON lc.material_id = r.material_id
     AND lc.start_offset_in_seconds IS NOT DISTINCT FROM r.start_offset_in_seconds
    -- LEFT so a material without imposition groups stays visible.
    LEFT JOIN cte_imposition im
           ON im.material_id = r.material_id
    ORDER BY
        r.start_offset_in_seconds,
        r.material_name,
        r.tenant_id,
        r.nest_plan_date,
        r.occurence,
        im.imposition_grouping_key;
END;
$$;

alter function get_nest_schedule(timestamp with time zone, text, integer, integer) owner to xfw3;

