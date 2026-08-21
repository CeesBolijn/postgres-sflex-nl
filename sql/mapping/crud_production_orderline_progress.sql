create function mapping.crud_production_orderline_progress(p_param_json jsonb, p_no_results boolean DEFAULT false) returns TABLE(param_id integer, track_by integer, crud text, domain_id integer, production_orderline_id integer, status_path integer[], status_times integer[], part_statuses integer[], part_amount integer[], operation_progress_status_sequences integer[], operation_progress_remaining_amounts integer[], updated_at timestamp with time zone)
	language plpgsql
as $$
DECLARE
    last_updated timestamp;
    has_status_path boolean := false;
    has_part_statuses boolean := false;
BEGIN

  SELECT
    bool_or(el ? 'status_path'),
    bool_or(el ? 'part_statuses')
  INTO has_status_path, has_part_statuses
  FROM jsonb_array_elements(p_param_json) AS el;

  CREATE TEMP TABLE param_table ON COMMIT DROP AS
  SELECT
    row_number() OVER ()::integer AS param_id,
    COALESCE(NULLIF(el->>'track_by', '')::integer, 0) AS track_by,
    el->>'crud' AS crud,
    NULLIF(el->>'domain_id', '')::integer AS domain_id,
    (el->>'production_orderline_id')::integer AS production_orderline_id,
    CASE WHEN el ? 'status_path' AND NULLIF(el->>'status_path', '') IS NOT NULL
         THEN (SELECT array_agg(NULLIF(v, '')::integer) FROM unnest(string_to_array(el->>'status_path', ',')) v WHERE v != '')::integer[]
         ELSE NULL
    END AS status_path,
    CASE WHEN el ? 'status_times' AND NULLIF(el->>'status_times', '') IS NOT NULL
         THEN (SELECT array_agg(NULLIF(v, '')::integer) FROM unnest(string_to_array(el->>'status_times', ',')) v WHERE v != '')::integer[]
         ELSE NULL
    END AS status_times,
    CASE WHEN el ? 'part_statuses' AND NULLIF(el->>'part_statuses', '') IS NOT NULL
         THEN (SELECT array_agg(NULLIF(v, '')::integer) FROM unnest(string_to_array(el->>'part_statuses', ',')) v WHERE v != '')::integer[]
         ELSE NULL
    END AS part_statuses,
    -- part_amount is now integer[]; parsed the same way as the other array columns
    CASE WHEN el ? 'part_amount' AND NULLIF(el->>'part_amount', '') IS NOT NULL
         THEN (SELECT array_agg(NULLIF(v, '')::integer) FROM unnest(string_to_array(el->>'part_amount', ',')) v WHERE v != '')::integer[]
         ELSE NULL
    END AS part_amount,
    -- part_amount is now integer[]; parsed the same way as the other array columns
    CASE WHEN el ? 'operation_progress_status_sequences' AND NULLIF(el->>'operation_progress_status_sequences', '') IS NOT NULL
         THEN (SELECT array_agg(NULLIF(v, '')::integer) FROM unnest(string_to_array(el->>'operation_progress_status_sequences', ',')) v WHERE v != '')::integer[]
         ELSE NULL
    END AS operation_progress_status_sequences,
    -- part_amount is now integer[]; parsed the same way as the other array columns
    CASE WHEN el ? 'operation_progress_remaining_amounts' AND NULLIF(el->>'operation_progress_remaining_amounts', '') IS NOT NULL
         THEN (SELECT array_agg(NULLIF(v, '')::integer) FROM unnest(string_to_array(el->>'operation_progress_remaining_amounts', ',')) v WHERE v != '')::integer[]
         ELSE NULL
    END AS operation_progress_remaining_amounts,
    NULLIF(el->>'updated_at', '')::timestamp AS updated_at
  FROM jsonb_array_elements(p_param_json) AS el;

  INSERT INTO mapping.production_orderline_progress AS polp (
    domain_id, production_orderline_id, status_path, status_times, part_statuses, part_amount, operation_progress_status_sequences, operation_progress_remaining_amounts, updated_at
  )
  SELECT
    pt.domain_id, pt.production_orderline_id, pt.status_path, pt.status_times, pt.part_statuses, pt.part_amount, pt.operation_progress_status_sequences, pt.operation_progress_remaining_amounts, pt.updated_at
  FROM param_table pt
  WHERE pt.crud = 'merge'
  ON CONFLICT ON CONSTRAINT production_orderline_progress_pkey DO UPDATE SET
    status_path   = COALESCE(EXCLUDED.status_path, polp.status_path),
    status_times  = COALESCE(EXCLUDED.status_times, polp.status_times),
    part_statuses = COALESCE(EXCLUDED.part_statuses, polp.part_statuses),
    part_amount   = COALESCE(EXCLUDED.part_amount, polp.part_amount),
    operation_progress_status_sequences = COALESCE(EXCLUDED.operation_progress_status_sequences, polp.operation_progress_status_sequences),
    operation_progress_remaining_amounts = COALESCE(EXCLUDED.operation_progress_remaining_amounts, polp.operation_progress_remaining_amounts),
    updated_at    = EXCLUDED.updated_at;

  SELECT MAX(pt.updated_at)
  INTO last_updated
  FROM param_table pt;

  IF has_status_path AND last_updated IS NOT NULL THEN
    UPDATE mapping.persistent_vars
    SET value = last_updated
    WHERE key = 'last_production_orderline_status_path_updated_at';
  END IF;

  IF has_part_statuses AND last_updated IS NOT NULL THEN
    UPDATE mapping.persistent_vars
    SET value = last_updated
    WHERE key = 'last_production_orderline_part_statuses_updated_at';
  END IF;

  IF NOT p_no_results THEN
    RETURN QUERY
    SELECT pt.param_id, pt.track_by, pt.crud, pt.domain_id,
           pt.production_orderline_id, pt.status_path, pt.status_times, pt.part_statuses,
           pt.part_amount, pt.operation_progress_status_sequences, pt.operation_progress_remaining_amounts, pt.updated_at::timestamptz
    FROM param_table pt
    ORDER BY pt.param_id;
  END IF;

END;
$$;

alter function mapping.crud_production_orderline_progress(jsonb, boolean) owner to xfw3;

