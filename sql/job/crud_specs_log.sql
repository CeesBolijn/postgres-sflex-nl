create function job.crud_specs_log(p_param_json jsonb) returns TABLE(specs_id integer, crud text, resource_uid text, printer_system_name text, fetched_at text, batch_no text, result text)
	language plpgsql
as $$
DECLARE
  _created int[];
  _updated int[];
BEGIN
  -- ── create: nieuwe batches ──
--   WITH new_rows AS (
--     INSERT INTO job.specs (specs_json, status)
--     SELECT e.val -> 'data', '{}'::int[]
--       FROM jsonb_array_elements(p_param_json) AS e(val)
--      WHERE e.val ->> 'crud' = 'create'
--        AND NOT EXISTS (
--          SELECT 1 FROM job.specs s
--           WHERE s.specs_json ->> 'type'     = 'durst-ink-batch'
--             AND s.specs_json ->> 'batch_no' = e.val -> 'data' ->> 'batch_no'
--        )
--     RETURNING job.specs.specs_id
--   )
--   SELECT array_agg(new_rows.specs_id) INTO _created FROM new_rows;
--
--   -- ── update: delta berekenen en loggen ──
--   WITH matched AS (
--     SELECT s.specs_id,
--            (e.val -> 'data' ->> 'amount_used_percentage')::numeric
--              - coalesce((s.specs_json ->> 'amount_used_percentage')::numeric, 0) AS delta,
--            e.val -> 'data' AS new_data
--       FROM jsonb_array_elements(p_param_json) AS e(val)
--       JOIN job.specs s
--         ON s.specs_json ->> 'type'                  = 'durst-ink-batch'
--        AND s.specs_json ->> 'resource_uid'           = e.val -> 'data' ->> 'resource_uid'
--        AND s.specs_json ->> 'ink_configuration_id'   = e.val -> 'data' ->> 'ink_configuration_id'
--        AND NOT (1000 = ANY(s.status))
--      WHERE e.val ->> 'crud' = 'update'
--   ),
--   logged AS (
--     INSERT INTO job.specs_log (specs_id, specs_log_json, created_at)
--     SELECT m.specs_id,
--            m.new_data || jsonb_build_object('amount', m.delta),
--            now()
--       FROM matched m
--      WHERE m.delta > 0
--     RETURNING job.specs_log.specs_id
--   ),
--   synced AS (
--     UPDATE job.specs s
--        SET specs_json = s.specs_json || jsonb_build_object(
--              'amount_used_percentage', (m.new_data ->> 'amount_used_percentage')::numeric,
--              'fetched_at',             m.new_data ->> 'fetched_at'
--            )
--       FROM matched m
--      WHERE s.specs_id = m.specs_id
--        AND m.delta > 0
--     RETURNING s.specs_id
--   )
--   SELECT array_agg(logged.specs_id) INTO _updated FROM logged;

  -- ── return alles ──
  RETURN QUERY
  SELECT null, null, null, null, null, null, null;

END;
$$;

alter function job.crud_specs_log(jsonb) owner to xfw3;

