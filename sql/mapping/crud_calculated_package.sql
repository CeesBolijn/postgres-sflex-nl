create function crud_calculated_package(p_param_json jsonb, p_no_results boolean DEFAULT false) returns TABLE(param_id integer, track_by integer, crud text, calculated_package_id bigint, domain_id integer, order_id bigint, address_country character varying, deleted_at timestamp with time zone, updated_at timestamp with time zone)
	language plpgsql
as $$
DECLARE
  last_updated_at timestamp;
BEGIN

  RETURN QUERY
  INSERT INTO mapping.calculated_package (
    calculated_package_id, domain_id, order_id,
    address_country, deleted_at, updated_at
  )
  SELECT
    (merged->>'calculated_package_id')::bigint,
    (merged->>'domain_id')::integer,
    (merged->>'order_id')::bigint,
    (merged->>'address_country')::varchar,
    (merged->>'deleted_at')::timestamp with time zone,
    (merged->>'updated_at')::timestamp with time zone
  FROM (
    SELECT
      jsonb_object_agg(key, jval)
        FILTER (WHERE key NOT IN ('crud', 'param_id', 'track_by')) AS merged
    FROM jsonb_array_elements(p_param_json) WITH ORDINALITY AS el(val, ord)
    CROSS JOIN LATERAL jsonb_each(val) AS kv(key, jval)
    WHERE val->>'crud' = 'merge'
    GROUP BY val
  ) s
  ON CONFLICT ON CONSTRAINT calculated_package_pkey DO UPDATE SET
    domain_id = COALESCE(EXCLUDED.domain_id, mapping.calculated_package.domain_id),
    order_id = COALESCE(EXCLUDED.order_id, mapping.calculated_package.order_id),
    address_country = COALESCE(EXCLUDED.address_country, mapping.calculated_package.address_country),
    deleted_at = COALESCE(EXCLUDED.deleted_at, mapping.calculated_package.deleted_at),
    updated_at = COALESCE(EXCLUDED.updated_at, now())
  RETURNING
    NULL::integer,
    NULL::integer,
    'merged'::text,
    mapping.calculated_package.calculated_package_id,
    mapping.calculated_package.domain_id,
    mapping.calculated_package.order_id,
    mapping.calculated_package.address_country,
    mapping.calculated_package.deleted_at,
    mapping.calculated_package.updated_at;

    SELECT MAX((v.value->>'updated_at')::timestamp)
    INTO last_updated_at
    FROM jsonb_array_elements(p_param_json) AS v(value)
    WHERE v.value->>'updated_at' IS NOT NULL;

    IF last_updated_at IS NOT NULL THEN
    UPDATE mapping.persistent_vars
    SET value = (last_updated_at - INTERVAL '2 minutes')::text
    WHERE key = 'last_sync_calculated_package_updated_at';
    END IF;


  IF p_no_results THEN RETURN; END IF;

END;
$$;

alter function crud_calculated_package(jsonb, boolean) owner to xfw3;

