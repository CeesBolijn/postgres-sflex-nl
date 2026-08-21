create function mapping.crud_internal_status(p_param_json jsonb, p_no_results boolean DEFAULT false) returns TABLE(param_id integer, track_by integer, crud text, domain_id integer, internal_status_id integer, code text, sequence integer, internal_title text, group_name text, updated_at timestamp with time zone)
	language plpgsql
as $$
#variable_conflict use_column
BEGIN

  IF p_no_results THEN
    INSERT INTO mapping.internal_status AS ist (
      domain_id, internal_status_id, code, sequence, internal_title, group_name
    )
    SELECT
      (el->>'domain_id')::integer,
      (el->>'internal_status_id')::integer,
      el->>'code',
      (el->>'sequence')::integer,
      el->>'internal_title',
      el->>'group_name'
    FROM jsonb_array_elements(p_param_json) AS el
    WHERE el->>'crud' = 'merge'
    ON CONFLICT (internal_status_id) DO UPDATE SET
      domain_id      = COALESCE(EXCLUDED.domain_id, ist.domain_id),
      code           = COALESCE(EXCLUDED.code, ist.code),
      sequence       = COALESCE(EXCLUDED.sequence, ist.sequence),
      internal_title = COALESCE(EXCLUDED.internal_title, ist.internal_title),
      group_name     = COALESCE(EXCLUDED.group_name, ist.group_name),
      updated_at     = now();
    RETURN;
  END IF;

  RETURN QUERY
  WITH src AS (
    SELECT
      (el->>'param_id')::integer           AS param_id,
      (el->>'track_by')::integer           AS track_by,
      (el->>'domain_id')::integer          AS domain_id,
      (el->>'internal_status_id')::integer AS internal_status_id,
      el->>'code'                          AS code,
      (el->>'sequence')::integer           AS sequence,
      el->>'internal_title'                AS internal_title,
      el->>'group_name'                    AS group_name
    FROM jsonb_array_elements(p_param_json) AS el
    WHERE el->>'crud' = 'merge'
  ),
  upserted AS (
    INSERT INTO mapping.internal_status AS ist (
      domain_id, internal_status_id, code, sequence, internal_title, group_name
    )
    SELECT
      src.domain_id, src.internal_status_id, src.code,
      src.sequence, src.internal_title, src.group_name
    FROM src
    ON CONFLICT (internal_status_id) DO UPDATE SET
      domain_id      = COALESCE(EXCLUDED.domain_id, ist.domain_id),
      code           = COALESCE(EXCLUDED.code, ist.code),
      sequence       = COALESCE(EXCLUDED.sequence, ist.sequence),
      internal_title = COALESCE(EXCLUDED.internal_title, ist.internal_title),
      group_name     = COALESCE(EXCLUDED.group_name, ist.group_name),
      updated_at     = now()
    RETURNING
      ist.domain_id,
      ist.internal_status_id,
      ist.code,
      ist.sequence,
      ist.internal_title,
      ist.group_name,
      ist.updated_at
  )
  SELECT
    src.param_id,
    src.track_by,
    'merged'::text                  AS crud,
    u.domain_id,
    u.internal_status_id,
    u.code::text                    AS code,
    u.sequence,
    u.internal_title::text          AS internal_title,
    u.group_name::text              AS group_name,
    u.updated_at
  FROM upserted u
  JOIN src ON src.internal_status_id = u.internal_status_id;

END;
$$;

alter function mapping.crud_internal_status(jsonb, boolean) owner to xfw3;

