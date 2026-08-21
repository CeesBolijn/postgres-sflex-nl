create function legacy.get_nest_planning(p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_line_type text DEFAULT NULL::text) returns TABLE(bucket_name text, production_line_id integer, resource_uid text, resource_name text, batch_id integer, material_id integer, name text, waste_percentage numeric, amount numeric, start_at timestamp with time zone, duration_seconds integer, interval_date date, class_names text[], batch_status_json jsonb)
	stable
	language sql
as $$
    -- #variable_conflict use_column

    WITH
    params AS (
        SELECT COALESCE(p_from, now()) AS from_ts
    ),
    plan_raw AS (
        SELECT
            (action_json->>'batch_id')::int AS batch_id,
            (action_json->>'name') AS name,
            (action_json->'data'->>'waste_percentage')::numeric AS waste_percentage,
            object.start_at,
            object.end_at,
            production_line.line_id AS production_line_id,
            resource.resource_uid,
            resource.resource_json->>'name' AS resource_name
        FROM action.object
        JOIN relation.resource
          ON (object.action_json->>'resource_id')::int = (resource.resource_json->>'pv2_id')::int
        JOIN relation.production_line
          ON production_line.line_id = resource.line_id
         AND (p_line_type IS NULL OR production_line.line_type = p_line_type)
        CROSS JOIN params
        WHERE (object.action_json->'data'->>'material_id')::int IS NOT NULL
          AND resource.step = 'print'
          AND object.start_at >= params.from_ts
          AND object.start_at <  params.from_ts + INTERVAL '1 day'
    ),
    plan AS (
        SELECT
            production_line_id,
            resource_uid,
            resource_name,
            batch_id,
            min(name) AS name,
            min(waste_percentage) AS waste_percentage,
            min(start_at) AS start_at,
            FLOOR(EXTRACT(EPOCH FROM sum(end_at - start_at)))::integer AS duration_seconds
        FROM plan_raw
        GROUP BY production_line_id, resource_uid, resource_name, batch_id
    ),
    batch_material AS (
        SELECT DISTINCT ON (batch_id)
            (action_json->>'batch_id')::int AS batch_id,
            (action_json->'data'->>'material_id')::int AS material_id
        FROM action.object
        JOIN relation.resource
          ON (object.action_json->>'resource_id')::int = (resource.resource_json->>'pv2_id')::int
        JOIN relation.production_line
          ON production_line.line_id = resource.line_id
         AND (p_line_type IS NULL OR production_line.line_type = p_line_type)
        CROSS JOIN params
        WHERE (object.action_json->'data'->>'material_id')::int IS NOT NULL
          AND resource.step = 'print'
          AND object.start_at >= params.from_ts
          AND object.start_at <  params.from_ts + INTERVAL '1 day'
        ORDER BY batch_id, material_id
    ),
    batch_interval AS (
        SELECT
            bm.batch_id,
            (
                SELECT interval_date
                FROM action.get_interval_dates(
                    p_reference_date  => mps.interval_start_date,
                    p_current_date    => params.from_ts::date,
                    p_interval        => mps.interval_days, 
                    p_look_ahead_days => 1,
                    p_day_offset      => 0
                )
            ) AS interval_date
        FROM batch_material bm
        JOIN mock.material_print_schedule mps
          ON bm.material_id = mps.material_id
        CROSS JOIN params
    ),
    batch_nests AS (
        SELECT DISTINCT
            SUBSTR(nest.nest_json->>'printfile_name', STRPOS(nest.nest_json->>'printfile_name', '_') + 1) AS bucket_name,
            plan.production_line_id,
            plan.resource_uid,
            plan.resource_name,
            plan.batch_id,
            plan.name,
            plan.waste_percentage,
            plan.start_at,
            plan.duration_seconds,
            nest.nest_id,
            nest.amount
        FROM legacy.nest
        JOIN plan
          ON nest.batch_id = plan.batch_id
    ),
    batch_amount AS (
        SELECT batch_id, sum(amount) AS amount
        FROM (SELECT DISTINCT batch_id, nest_id, amount FROM batch_nests) x
        GROUP BY batch_id
    ),
    alert_from AS (
        SELECT interval_date
        FROM params
        CROSS JOIN action.get_interval_dates(
            p_reference_date  => params.from_ts::date,
            p_current_date    => params.from_ts::date,
            p_interval        => 1,
            p_look_ahead_days => 1,
            p_day_offset      => 2
        )
    ),
    batch_alert AS (
        SELECT
            bn.batch_id,
            bool_or(cs.production_date::date > alert_from.interval_date) AS has_alert
        FROM batch_nests bn
        JOIN legacy.single_product sp
          ON sp.nest_id = bn.nest_id
        JOIN mapping.component_specs cs
          ON cs.production_orderline_id = sp.production_orderline_id
        CROSS JOIN alert_from
        GROUP BY bn.batch_id
    ),
    log AS (
        SELECT nl.*
        FROM legacy.nest_log nl
        WHERE nl.batch_id IN (SELECT batch_id FROM plan)
    ),
    inflow AS (
        SELECT batch_id, to_status_sequence AS sequence, sum(amount) AS in_amount
        FROM log
        GROUP BY batch_id, to_status_sequence
    ),
    outflow AS (
        SELECT batch_id, from_status_sequence AS sequence, sum(amount) AS out_amount
        FROM log
        GROUP BY batch_id, from_status_sequence
    ),
    last_inflow AS (
        SELECT DISTINCT ON (batch_id, to_status_sequence)
            batch_id,
            to_status_sequence AS sequence,
            moved_at      AS last_moved_at,
            resource_uids AS last_resource_uids
        FROM log
        ORDER BY batch_id, to_status_sequence, moved_at DESC
    ),
    batches_x_status AS (
        SELECT b.batch_id, s.code, s.sequence
        FROM (SELECT DISTINCT batch_id FROM batch_nests) b
        CROSS JOIN mapping.internal_status s
    ),
    balances AS (
        SELECT
            bxs.batch_id,
            bxs.code,
            bxs.sequence,
            COALESCE(inflow.in_amount, 0) - COALESCE(outflow.out_amount, 0) AS current_amount,
            last_inflow.last_moved_at,
            last_inflow.last_resource_uids
        FROM batches_x_status bxs
        LEFT JOIN inflow
          ON inflow.batch_id = bxs.batch_id AND inflow.sequence = bxs.sequence
        LEFT JOIN outflow
          ON outflow.batch_id = bxs.batch_id AND outflow.sequence = bxs.sequence
        LEFT JOIN last_inflow
          ON last_inflow.batch_id = bxs.batch_id AND last_inflow.sequence = bxs.sequence
    ),
    batch_status AS (
        SELECT
            batch_id,
            jsonb_agg(
                jsonb_build_object(
                    'code', code,
                    'sequence', sequence,
                    'current_amount', current_amount,
                    'last_moved_at', last_moved_at,
                    'last_resource_uids', last_resource_uids
                )
                ORDER BY sequence
            ) AS batch_status_json
        FROM balances
        WHERE current_amount > 0
        GROUP BY batch_id
    )
    SELECT DISTINCT
        bn.bucket_name,
        bn.production_line_id,
        bn.resource_uid,
        bn.resource_name,
        bn.batch_id,
        bm.material_id,
        bn.name,
        bn.waste_percentage,
        ba.amount,
        bn.start_at,
        bn.duration_seconds,
        COALESCE(bi.interval_date, params.from_ts::date) AS interval_date,
        NULLIF(
            ARRAY_REMOVE(
                ARRAY[
                    CASE WHEN COALESCE(bal.has_alert, false) THEN 'plan-warning' END,
                    CASE WHEN COALESCE(bi.interval_date, params.from_ts::date) <> params.from_ts::date THEN 'plan-alert' END
                ],
                NULL
            ),
            ARRAY[]::text[]
        ) AS class_names,
        bs.batch_status_json
    FROM batch_nests bn
    CROSS JOIN params
    LEFT JOIN batch_amount   ba  ON ba.batch_id = bn.batch_id
    LEFT JOIN batch_material bm  ON bm.batch_id = bn.batch_id
    LEFT JOIN batch_status   bs  ON bs.batch_id = bn.batch_id
    LEFT JOIN batch_interval bi  ON bi.batch_id = bn.batch_id
    LEFT JOIN batch_alert    bal ON bal.batch_id = bn.batch_id
    ORDER BY bn.production_line_id, bn.resource_uid, bn.bucket_name, bn.batch_id;
$$;

alter function legacy.get_nest_planning(timestamp with time zone, text) owner to xfw3;

