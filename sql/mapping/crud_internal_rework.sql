create function mapping.crud_internal_rework(p_param_json jsonb, p_no_results boolean DEFAULT false) returns TABLE(param_id integer, track_by integer, crud text, rework_id bigint, domain_id integer, order_id integer, order_log_id integer, object_type text, object_id integer, object_sequence integer, object_reference text, object_amount integer, production_unit_id integer, production_line_id integer, internal_status_code text, side text, rework_incident_date timestamp with time zone, created_at timestamp with time zone, updated_at timestamp with time zone, deleted_at timestamp with time zone, production_orderline_id integer)
	language plpgsql
as $$
DECLARE
  last_updated_at timestamp;
BEGIN

  RETURN QUERY
  INSERT INTO mapping.internal_rework (
    internal_rework_id, domain_id, order_id, order_log_id,
    object_type, object_id, object_sequence, object_reference,
    object_amount, production_unit_id, production_line_id,
    internal_status_code, side, rework_incident_date,
    created_at, updated_at, production_orderline_id
  )
  SELECT
    (merged->>'internal_rework_id')::integer,
    (merged->>'domain_id')::integer,
    (merged->>'order_id')::integer,
    (merged->>'order_log_id')::integer,
    merged->>'object_type',
    (merged->>'object_id')::integer,
    (merged->>'object_sequence')::integer,
    merged->>'object_reference',
    (merged->>'object_amount')::integer,
    (merged->>'production_unit_id')::integer,
    (merged->>'production_line_id')::integer,
    merged->>'internal_status_code',
    merged->>'side',
    (merged->>'rework_incident_date')::timestamp with time zone,
    now(),
    COALESCE((merged->>'updated_at')::timestamp with time zone, now()),
    (merged->>'production_orderline_id')::integer
  FROM (
    SELECT
      jsonb_object_agg(key, jval)
        FILTER (WHERE key NOT IN ('crud', 'param_id', 'track_by')) AS merged
    FROM jsonb_array_elements(p_param_json) WITH ORDINALITY AS el(val, ord)
    CROSS JOIN LATERAL jsonb_each(val) AS kv(key, jval)
    WHERE val->>'crud' = 'merge'
    GROUP BY val
  ) s
  ON CONFLICT (internal_rework_id) DO UPDATE SET
    domain_id = COALESCE(EXCLUDED.domain_id, mapping.internal_rework.domain_id),
    order_id = COALESCE(EXCLUDED.order_id, mapping.internal_rework.order_id),
    order_log_id = COALESCE(EXCLUDED.order_log_id, mapping.internal_rework.order_log_id),
    object_type = COALESCE(EXCLUDED.object_type, mapping.internal_rework.object_type),
    object_id = COALESCE(EXCLUDED.object_id, mapping.internal_rework.object_id),
    object_sequence = COALESCE(EXCLUDED.object_sequence, mapping.internal_rework.object_sequence),
    object_reference = COALESCE(EXCLUDED.object_reference, mapping.internal_rework.object_reference),
    object_amount = COALESCE(EXCLUDED.object_amount, mapping.internal_rework.object_amount),
    production_unit_id = COALESCE(EXCLUDED.production_unit_id, mapping.internal_rework.production_unit_id),
    production_line_id = COALESCE(EXCLUDED.production_line_id, mapping.internal_rework.production_line_id),
    internal_status_code = COALESCE(EXCLUDED.internal_status_code, mapping.internal_rework.internal_status_code),
    side = COALESCE(EXCLUDED.side, mapping.internal_rework.side),
    rework_incident_date = COALESCE(EXCLUDED.rework_incident_date, mapping.internal_rework.rework_incident_date),
    updated_at = COALESCE(EXCLUDED.updated_at, now()),
    production_orderline_id = COALESCE(EXCLUDED.production_orderline_id, mapping.internal_rework.production_orderline_id)
  RETURNING
    NULL::integer,
    NULL::integer,
    'merged'::text,
    mapping.internal_rework.internal_rework_id::bigint,
    mapping.internal_rework.domain_id,
    mapping.internal_rework.order_id,
    mapping.internal_rework.order_log_id,
    mapping.internal_rework.object_type,
    mapping.internal_rework.object_id,
    mapping.internal_rework.object_sequence,
    mapping.internal_rework.object_reference,
    mapping.internal_rework.object_amount,
    mapping.internal_rework.production_unit_id,
    mapping.internal_rework.production_line_id,
    mapping.internal_rework.internal_status_code,
    mapping.internal_rework.side,
    mapping.internal_rework.rework_incident_date,
    mapping.internal_rework.created_at,
    mapping.internal_rework.updated_at,
    mapping.internal_rework.deleted_at,
    mapping.internal_rework.production_orderline_id;

    SELECT MAX((v.value->>'updated_at')::timestamp)
    INTO last_updated_at
    FROM jsonb_array_elements(p_param_json) AS v(value)
    WHERE v.value->>'updated_at' IS NOT NULL;

    IF last_updated_at IS NOT NULL THEN
    UPDATE mapping.persistent_vars
    SET value = (last_updated_at - INTERVAL '2 minutes')::text
    WHERE key = 'last_internal_rework_updated_at';
    END IF;

  IF p_no_results THEN RETURN; END IF;

END;
$$;

alter function mapping.crud_internal_rework(jsonb, boolean) owner to xfw3;

