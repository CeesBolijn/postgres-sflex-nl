create function get_resource_plan_batch(p_resource_uids text[] DEFAULT NULL::text[], p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_until timestamp with time zone DEFAULT now(), p_line_type text DEFAULT NULL::text) returns TABLE(resource_uid text, state jsonb, group_state jsonb, layout_name text, step text, name text, nest_name text, filename text, page_number integer, batch_id integer, batch_name text, data jsonb, start_at timestamp with time zone, offset_seconds numeric, duration_seconds numeric)
	stable
	language plpgsql
as $$
DECLARE
    v_lookup_json       jsonb;
    v_group_state_json  jsonb;
    v_day               date;
BEGIN
    v_day := coalesce(p_until::date, current_date);
      -- run to the end of the selected day, but never later than the current time
    p_until := (v_day + 1)::timestamp at time zone 'Europe/Amsterdam';
    p_from := coalesce(p_from, (v_day::timestamp + interval '6 hours') at time zone 'Europe/Amsterdam');

    v_day   := COALESCE(p_until::date, CURRENT_DATE);
    p_until := COALESCE(p_until, ((v_day + 1)::timestamp AT TIME ZONE 'Europe/Amsterdam'));
    p_from  := COALESCE(p_from,  (v_day::timestamp + interval '6 hours') AT TIME ZONE 'Europe/Amsterdam');

    IF p_line_type IS NOT NULL AND array_length(p_resource_uids, 1) IS NULL THEN
        SELECT array_agg(r.resource_uid)
          INTO p_resource_uids
          FROM relation.resource        r
          JOIN relation.production_line pl ON pl.line_id = r.line_id
         WHERE pl.line_type = p_line_type;
    END IF;

    SELECT lk.lookup_json INTO v_lookup_json
      FROM relation.lookup lk
     WHERE lk.lookup = 'lookup_resource_state'
     LIMIT 1;

    SELECT lk.lookup_json INTO v_group_state_json
      FROM relation.lookup lk
     WHERE lk.lookup = 'lookup_resource_group_state'
     LIMIT 1;

    RETURN QUERY
    WITH nests AS (
        SELECT
            obj.action_json ->>'name'        AS batch_name,
            obj.action_json                  AS action_json,
            obj.start_at                     AS start_at,
            obj.action_json ->>'resource_id' AS resource_id,
            (obj.action_json ->>'batch_id')::integer    AS batch_id,
            COALESCE(
                (SELECT jsonb_agg(
                    ba.value
                    || jsonb_build_object(
                        'total_amount',         n.amount::numeric,
                        'internal_status_code', n.nest_json ->>'internal_status_code',
                        'updated_at',           n.nest_json ->>'updated_at'
                    )
                    ORDER BY (ba.value ->>'sequence')::int
                )
                FROM jsonb_array_elements(obj.action_json -> 'data' -> 'batched_amounts') AS ba(value)
                LEFT JOIN legacy.nest n ON n.nest_id = (ba.value ->>'nest_id')::bigint
                ),
                '[]'::jsonb
            ) AS batched_amounts
        FROM action.object obj
    ),
    nest_status AS (
        SELECT
            n.batch_id,
            n.batch_name,
            n.action_json,
            n.start_at,
            n.resource_id,
            n.batched_amounts,
            (SELECT mis.code
             FROM jsonb_array_elements(n.batched_amounts) ba
             JOIN mapping.internal_status mis ON mis.code = (ba->>'internal_status_code')
             ORDER BY mis.sequence
             LIMIT 1)                        AS internal_status_code,
            (SELECT jsonb_agg(jsonb_build_object(
                'internal_status_code', s.status_code,
                'amount',               s.amount,
                'sequence',             s.sequence
            ))
             FROM (
                 SELECT
                     (ba->>'internal_status_code')   AS status_code,
                     SUM((ba->>'total_amount')::int) AS amount,
                     MIN(mis.sequence)               AS sequence
                 FROM jsonb_array_elements(n.batched_amounts) ba
                 JOIN mapping.internal_status mis ON mis.code = (ba->>'internal_status_code')
                 GROUP BY (ba->>'internal_status_code')
             ) s)                            AS nest_status
        FROM nests n
    ),
    resolved_state AS (
        SELECT
            ns.*,
            COALESCE(
                (SELECT s.value
                 FROM jsonb_array_elements(v_lookup_json)        AS ss(value),
                      jsonb_array_elements(ss.value -> 'states') AS s(value)
                 WHERE s.value ->>'code' = ns.internal_status_code
                 LIMIT 1),
                (SELECT s.value
                 FROM jsonb_array_elements(v_lookup_json)        AS ss(value),
                      jsonb_array_elements(ss.value -> 'states') AS s(value)
                 WHERE s.value ->>'code' = COALESCE(
                     NULLIF(ns.action_json ->>'status', ''),
                     ns.action_json ->>'type',
                     'batch'
                 )
                 LIMIT 1)
            ) AS resolved_state_json
        FROM nest_status ns
    )
    SELECT
        res.resource_uid,
        rs.resolved_state_json,
        (SELECT gs.value
         FROM jsonb_array_elements(v_group_state_json) AS gs(value)
         WHERE gs.value ->>'code' = rs.resolved_state_json ->>'group'
         LIMIT 1),
        res.resource_json ->>'layout_name',
        res.resource_json ->>'step',
        res.resource_json ->>'name',
        NULL::text,
        NULL::text,
        NULL::integer,
        rs.batch_id,
        rs.batch_name,
        jsonb_set(rs.action_json -> 'data', '{batched_amounts}', rs.batched_amounts)
            || jsonb_build_object(
                'internal_status_code', rs.internal_status_code,
                'nest_status',          rs.nest_status
            ),
        rs.start_at,
        EXTRACT(EPOCH FROM (rs.start_at - p_from))::numeric,
        (rs.action_json ->>'duration')::numeric * 60
    FROM resolved_state rs
    JOIN relation.resource res
      ON rs.resource_id = res.resource_json ->>'pv2_id'
    JOIN relation.production_line pl
      ON res.line_id = pl.line_id
    WHERE res.resource_uid = ANY(p_resource_uids)
      --AND rs.action_json -> 'data' ->> 'internal_status_code' <> 'order_announced'
      AND rs.start_at >= p_from
      AND rs.start_at <  p_until
    ORDER BY rs.start_at;
END;
$$;

alter function get_resource_plan_batch(text[], timestamp with time zone, timestamp with time zone, text) owner to xfw3;

