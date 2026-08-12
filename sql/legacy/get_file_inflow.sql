create function get_file_inflow(p_from timestamp with time zone, p_line_type text) returns TABLE(delivery_hours integer, threshold integer, threshold_json jsonb, cutoff_window_start_at timestamp with time zone, cutoff_window_end_at timestamp with time zone, hour_agg_json jsonb, total_files integer, total_sqm numeric, total_amount integer)
	stable
	language plpgsql
as $$
#variable_conflict use_column
DECLARE
    v_anchor_date date        := (p_from AT TIME ZONE 'UTC')::date;
    v_now         timestamptz := now();
BEGIN
    RETURN QUERY
    WITH classes AS (
        -- One representative row per group: MIN(delivery_hours) wins, and
        -- carries that row's cut_off_time, threshold and threshold_json.
        SELECT DISTINCT ON (ct.group_id)
               ct.group_id,
               ct.delivery_hours,
               ct.cut_off_time,
               ct.threshold,
               ct.threshold_json
        FROM legacy.cutoff_times AS ct
        WHERE ct.service_provider_id = 7
        ORDER BY ct.group_id, ct.delivery_hours
    ),
    tracks AS (
        -- One row per track: anchor day and next day for every threshold_json
        -- element ('all', or 'lte' + 'gt'). Ordinality keeps lte before gt.
        -- cut_off_time is timetz at +00, so date + timetz already resolves to
        -- an absolute instant. No AT TIME ZONE here: on a timestamptz it would
        -- strip the zone instead of attaching one.
        SELECT c.group_id,
               c.delivery_hours,
               (w.d + c.cut_off_time) AS window_end_at,
               el.value ->> 'code'    AS code,
               el.ord                 AS code_order,
               c.threshold,
               el.value               AS threshold_json
        FROM classes AS c
        CROSS JOIN LATERAL (VALUES (v_anchor_date), (v_anchor_date + 1)) AS w(d)
        CROSS JOIN LATERAL jsonb_array_elements(c.threshold_json)
                   WITH ORDINALITY AS el(value, ord)
    ),
    files AS (
        SELECT ud.uploader_data_id,
               ud.updated_at                                   AS received_at,
               MIN((mpl.line_json ->> 'rush_time_hours')::int) AS rush_time_hours,
               SUM(cs.product_amount)::int                     AS amount,
               SUM(ud.file_amount)::int                        AS file_amount,
               SUM(cs.sqm)::numeric                            AS sqm
        FROM mapping.uploader_data AS ud
        JOIN mapping.component_specs AS cs
          ON cs.uploader_data_id = ud.uploader_data_id
        JOIN mapping.material_production_line AS mpl
          ON mpl.material_id = cs.material_id
        JOIN relation.production_line AS pl
          ON pl.line_id = mpl.production_line_id
         AND pl.line_type = p_line_type
        WHERE ud.updated_at >= ((v_anchor_date - 1)::timestamp AT TIME ZONE 'UTC')
          AND ud.updated_at <  ((v_anchor_date + 2)::timestamp AT TIME ZONE 'UTC')
          AND (mpl.line_json ->> 'rush_time_hours')::int IS NOT NULL
        GROUP BY ud.uploader_data_id, ud.updated_at
    ),
    files_grouped AS (
        -- rush_time_hours -> group_id straight from cutoff_times (this is the
        -- per-delivery_hours mapping; no separate members CTE needed).
        SELECT f.received_at,
               f.amount,
               f.file_amount,
               f.sqm,
               ct.group_id
        FROM files AS f
        JOIN legacy.cutoff_times AS ct
          ON ct.delivery_hours      = f.rush_time_hours
         AND ct.service_provider_id = 7
    ),
    hour_counts AS (
        -- Membership is half-open on a full 24h: (end - 24h, end], so the
        -- minute between :30 and :31 cannot fall between two windows.
        SELECT t.group_id,
               t.window_end_at,
               t.code,
               date_trunc('hour', f.received_at, 'UTC') AS hour_at,
               SUM(f.file_amount)::int AS files,
               SUM(f.sqm)::numeric     AS sqm,
               SUM(f.amount)::int      AS amount
        FROM files_grouped AS f
        JOIN tracks AS t
          ON t.group_id = f.group_id
         AND f.received_at >  t.window_end_at - interval '24 hours'
         AND f.received_at <= t.window_end_at
         AND CASE t.code
                 WHEN 'all' THEN true
                 WHEN 'lte' THEN f.amount <= t.threshold
                 WHEN 'gt'  THEN f.amount >  t.threshold
             END
        GROUP BY t.group_id, t.window_end_at, t.code,
                 date_trunc('hour', f.received_at, 'UTC')
    )
    -- Hour buckets are generated per window so zero hours are present in the
    -- series; buckets after "now" are excluded (open windows stop at the last
    -- completed hour). Tracks whose window has no buckets yet still return,
    -- with an empty series. Reported start (end - 23:59) is display convention.
    SELECT t.delivery_hours,
           t.threshold,
           t.threshold_json,
           t.window_end_at - interval '23 hours 59 minutes' AS cutoff_window_start_at,
           t.window_end_at                                  AS cutoff_window_end_at,
           COALESCE(jsonb_agg(jsonb_build_object(
               'date_time', gs.hour_at,
               'amount',    COALESCE(hc.files, 0)
           ) ORDER BY gs.hour_at)
               FILTER (WHERE gs.hour_at IS NOT NULL), '[]'::jsonb) AS hour_agg_json,
           COALESCE(SUM(hc.files), 0)::int   AS total_files,
           COALESCE(SUM(hc.sqm), 0)::numeric AS total_sqm,
           COALESCE(SUM(hc.amount), 0)::int  AS total_amount
    FROM tracks AS t
    LEFT JOIN LATERAL generate_series(
        date_trunc('hour', t.window_end_at - interval '23 hours 59 minutes', 'UTC'),
        date_trunc('hour', t.window_end_at, 'UTC'),
        interval '1 hour') AS gs(hour_at)
      ON gs.hour_at <= date_trunc('hour', v_now, 'UTC')
    LEFT JOIN hour_counts AS hc
      ON hc.group_id      = t.group_id
     AND hc.window_end_at = t.window_end_at
     AND hc.code          = t.code
     AND hc.hour_at       = gs.hour_at
    GROUP BY t.group_id, t.delivery_hours, t.window_end_at, t.code, t.code_order,
             t.threshold, t.threshold_json
    ORDER BY t.window_end_at, t.delivery_hours, t.code_order;
END;
$$;

alter function get_file_inflow(timestamp with time zone, text) owner to xfw3;

