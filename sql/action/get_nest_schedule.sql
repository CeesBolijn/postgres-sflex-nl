create function action.get_nest_schedule(p_from timestamp with time zone, p_line_type text, p_threshold numeric DEFAULT 10) returns TABLE(board_date date, tenant_id integer, production_location text, material_id integer, material_name text, production_date timestamp without time zone, day_offset integer, hours_until_production numeric, group_code text, segment_seq integer, segment_day_offset integer, segment_start_offset_in_seconds integer, orderline_count integer, product_amount numeric, sqm numeric, sequence integer, status_json jsonb, impact_json jsonb, class_name text[])
	stable
	language plpgsql
as $$
#variable_conflict use_column
DECLARE
    v_domain_id                  integer := 1;
    v_time_zone                  text    := 'Europe/Amsterdam';
    v_min_sequence               integer := 100;   -- exclusive lower bound
    v_max_sequence               integer := 450;   -- inclusive upper bound (file_in_gangrun)
    v_ready_sequence             integer := 450;   -- at or above this the file has reached gangrun
    v_at_risk_days               integer := 5;
    v_horizon_days               integer := 14;
    v_workday_search_days        integer := 14;
    v_material_look_ahead_days   integer := 1;
    v_undivided_until_day_offset integer := 1;     -- day_offset 0..this stay one group
    v_max_delivery_time          integer := 96;    -- buckets stop here; anything further out lands in 96
    v_timeline_code              text    := 'nest-schedule';
    v_nest_moment_lookup         text    := 'lookup_nest_moments';
    v_tenant_name                jsonb   := jsonb_build_object('1', 'Dokkum', '2', 'Bad Hersfeld');

    v_board_date      date;
    v_reference_at    timestamptz;
    v_reference_local timestamp;
    v_reference_abs   integer;
BEGIN
    -- First same-or-next working day. get_interval_dates returns nothing for
    -- a weekend p_current_date, so it doubles as a working-day test here.
    SELECT min(d.candidate)::date
      INTO v_board_date
      FROM generate_series(
               (p_from AT TIME ZONE v_time_zone)::date::timestamp,
               ((p_from AT TIME ZONE v_time_zone)::date + v_workday_search_days)::timestamp,
               interval '1 day') AS d(candidate)
     WHERE EXISTS (SELECT 1 FROM action.get_interval_dates(d.candidate::date, d.candidate::date, 1, 1));

    IF v_board_date IS NULL THEN
        RETURN;
    END IF;

    -- One reference moment: p_from when it falls on the board day, otherwise
    -- that day's start.
    v_reference_at    := greatest(p_from, (v_board_date::timestamp AT TIME ZONE 'UTC'));
    v_reference_local := v_reference_at AT TIME ZONE v_time_zone;
    v_reference_abs   := EXTRACT(EPOCH FROM (v_reference_at - (v_board_date::timestamp AT TIME ZONE 'UTC')))::integer;

    RETURN QUERY
    WITH cte_line AS MATERIALIZED (
        SELECT
            pl.line_id, pl.line_type, pl.tenant_id,
            coalesce(v_tenant_name ->> pl.tenant_id::text, 'tenant-' || pl.tenant_id) AS production_location
        FROM relation.production_line pl
    ),

    -- MATERIALIZED: get_timeline_view_segments is VOLATILE, so without the
    -- fence the planner may re-invoke it per row.
    cte_schedule AS MATERIALIZED (
        SELECT
            row_number() OVER (ORDER BY s.day_offset, s.start_offset_in_seconds)::integer AS segment_seq,
            s.day_offset                                     AS segment_day_offset,
            s.start_offset_in_seconds                        AS segment_start_offset_in_seconds,
            s.day_offset * 86400 + s.start_offset_in_seconds AS segment_start_abs,
            s.day_offset * 86400 + s.end_offset_in_seconds   AS segment_end_abs
        FROM production.get_timeline_view_segments(v_timeline_code) s
    ),

    -- Nest moments from the lookup, capped at v_max_delivery_time. Six rows.
    -- Segment choice: containment first, nearest start as fallback -- the
    -- 18/24/30 moments hit their markers exactly, the evening moments sit
    -- 900s before the previous-day segment starts.
    cte_moment AS MATERIALIZED (
        SELECT mm.delivery_time, seg.segment_seq, seg.segment_day_offset, seg.segment_start_offset_in_seconds
        FROM (
            SELECT
                (nm.value ->> 'delivery_time')::integer AS delivery_time,
                coalesce((nm.value -> 'nest_time' ->> 'day_offset')::integer, 0) * 86400
                    + EXTRACT(EPOCH FROM (nm.value -> 'nest_time' ->> 'time')::timetz)::integer AS moment_abs
            FROM production.lookup l
            CROSS JOIN LATERAL jsonb_array_elements(l.lookup_json) AS nm(value)
            WHERE l.lookup = v_nest_moment_lookup
              AND jsonb_typeof(nm.value -> 'nest_time') = 'object'
              AND (nm.value ->> 'delivery_time')::integer <= v_max_delivery_time
        ) mm
        LEFT JOIN LATERAL (
            SELECT s.segment_seq, s.segment_day_offset, s.segment_start_offset_in_seconds
            FROM cte_schedule s
            ORDER BY (mm.moment_abs >= s.segment_start_abs AND mm.moment_abs < s.segment_end_abs) DESC,
                     abs(mm.moment_abs - s.segment_start_abs)
            LIMIT 1
        ) seg ON true
    ),

    -- Materials running on the board date. material_code is in the select
    -- list only because DISTINCT ON needs its ORDER BY items there.
    cte_material AS MATERIALIZED (
        SELECT DISTINCT ON (mps.material_id)
            mps.material_id, mps.material_name, mps.material_code, mps.resource_uids
        FROM mock.material_print_schedule mps
        JOIN action.get_interval_dates(mps.interval_start_date, v_board_date, mps.interval_days, v_material_look_ahead_days) gid
          ON gid.interval_date = v_board_date
        WHERE mps.production_line_id IN (SELECT line_id FROM cte_line WHERE line_type = p_line_type)
        ORDER BY mps.material_id, mps.production_line_id, mps.material_code
    ),

    -- The steps a material actually routes through, from its scheduled
    -- resources. DISTINCT: two resources can share a step.
    cte_material_step AS MATERIALIZED (
        SELECT DISTINCT m.material_id, r.step
        FROM cte_material m
        CROSS JOIN LATERAL jsonb_array_elements_text(m.resource_uids) AS ru(resource_uid)
        JOIN relation.resource r ON r.resource_uid = ru.resource_uid
        WHERE r.step IS NOT NULL
    ),

    cte_order AS (
        SELECT
            l.tenant_id, l.production_location,
            cs.material_id, m.material_name,
            cs.production_date,
            (cs.production_date::date - v_board_date)::integer AS day_offset,
            ist.sequence, cs.internal_status_code,
            cs.product_amount, cs.sqm,
            -- m1 = cut length per item x amount. ASSUMPTION: width/height are
            -- centimetres (50 x 70 gives sqm 0.35, so they are) and m1 is the
            -- perimeter. Change this one expression if m1 means something else.
            (2 * (coalesce(cs.product_width, 0) + coalesce(cs.product_height, 0)) / 100.0
                 * coalesce(cs.product_amount, 0))::numeric AS m1,
            (CASE
                WHEN (cs.production_date::date - v_board_date) <= v_undivided_until_day_offset THEN 'all'
                WHEN cs.sqm <= p_threshold                                                     THEN 'lte-threshold'
                ELSE 'gt-threshold'
             END) AS group_code
        FROM mapping.component_specs cs
        JOIN cte_material m ON m.material_id = cs.material_id
        JOIN mapping.internal_status ist
          ON ist.code = cs.internal_status_code AND ist.domain_id = cs.domain_id
        LEFT JOIN cte_line l ON l.line_id = cs.first_production_line_id
        WHERE cs.is_open = true
          AND cs.domain_id = v_domain_id
          AND ist.sequence >  v_min_sequence
          AND ist.sequence <= v_max_sequence
          AND cs.production_date::date <= v_board_date + v_horizon_days
    ),

    -- The grain: one row per tenant + material + production_date + group.
    cte_agg AS (
        SELECT
            o.tenant_id, o.production_location, o.material_id, o.material_name,
            o.production_date, o.day_offset, o.group_code,
            count(*)::integer            AS orderline_count,
            sum(o.product_amount)        AS product_amount,
            sum(o.sqm)                   AS sqm,
            sum(o.m1)                    AS m1,
            min(o.sequence)::integer     AS sequence,   -- least advanced = the bottleneck
            (EXTRACT(EPOCH FROM (o.production_date - v_reference_local)) / 3600.0)::numeric AS hours_until_production
        FROM cte_order o
        GROUP BY o.tenant_id, o.production_location, o.material_id, o.material_name,
                 o.production_date, o.day_offset, o.group_code
    ),

    -- Status spread per grain, for the distribution bar.
    cte_status AS (
        SELECT
            s.tenant_id, s.material_id, s.production_date, s.group_code,
            jsonb_agg(jsonb_build_object(
                'internal_status_code', s.internal_status_code,
                'sequence',             s.sequence,
                'orderline_count',      s.orderline_count
            ) ORDER BY s.sequence) AS status_json
        FROM (
            SELECT o.tenant_id, o.material_id, o.production_date, o.group_code,
                   o.internal_status_code, o.sequence, count(*)::integer AS orderline_count
            FROM cte_order o
            GROUP BY 1,2,3,4,5,6
        ) s
        GROUP BY 1,2,3,4
    )

    SELECT
        v_board_date,
        a.tenant_id,
        a.production_location,
        a.material_id,
        a.material_name,
        a.production_date,
        a.day_offset,
        round(a.hours_until_production, 2),
        a.group_code,
        cut.segment_seq,
        cut.segment_day_offset,
        cut.segment_start_offset_in_seconds,
        a.orderline_count,
        a.product_amount,
        round(a.sqm, 2),
        a.sequence,
        st.status_json,
        -- Same totals under every step the material routes through, so the
        -- front-end can show m2 for print/coat/laminate and m1 for cut/bin.
        coalesce((
            SELECT jsonb_object_agg(ms.step, jsonb_build_object('sqm', round(a.sqm, 2),
                                                                'm1',  round(a.m1, 2)))
            FROM cte_material_step ms
            WHERE ms.material_id = a.material_id
        ), '{}'::jsonb),
        -- Cumulative, least to most severe: all four may be present and the
        -- CSS cascade decides. That makes the stylesheet order load-bearing --
        -- declare ready -> pending -> at-risk -> delayed.
        ARRAY['state-ready']
          || CASE WHEN a.sequence < v_ready_sequence
                  THEN ARRAY['state-pending'] ELSE '{}'::text[] END
          || CASE WHEN a.sequence < v_ready_sequence AND a.day_offset <= v_at_risk_days
                  THEN ARRAY['state-at-risk'] ELSE '{}'::text[] END
          || CASE WHEN a.sequence < v_ready_sequence AND a.day_offset <= 0
                  THEN ARRAY['state-delayed'] ELSE '{}'::text[] END
    FROM cte_agg a
    LEFT JOIN cte_status st
           ON st.tenant_id       = a.tenant_id
          AND st.material_id     = a.material_id
          AND st.production_date = a.production_date
          AND st.group_code      = a.group_code
    -- The bucket follows the hours still left before production_date, capped
    -- at v_max_delivery_time so there is always a match.
    LEFT JOIN LATERAL (
        SELECT mo.segment_seq, mo.segment_day_offset, mo.segment_start_offset_in_seconds
        FROM cte_moment mo
        WHERE mo.delivery_time >= least(a.hours_until_production, v_max_delivery_time)
        ORDER BY mo.delivery_time
        LIMIT 1
    ) cut ON true
    ORDER BY a.tenant_id, a.material_name, a.production_date, a.group_code;
END;
$$;

alter function action.get_nest_schedule(timestamp with time zone, text, numeric) owner to xfw3;

