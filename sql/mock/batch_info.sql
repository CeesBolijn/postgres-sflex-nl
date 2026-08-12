create function batch_info(p_batch_id integer) returns jsonb
	language plpgsql
as $$
#variable_conflict use_column
BEGIN
  RETURN jsonb_build_object(
    'production_dates', COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object('production_date', t.production_date, 'amount', t.amount)
          ORDER BY t.production_date
        )
        FROM (
          SELECT
            cs.production_date,
            COUNT(*) AS amount
          FROM legacy.batch b
          JOIN legacy.nest n
            ON n.batch_uid = b.batch_uid
          JOIN legacy.single_product sp
            ON sp.nest_id = n.nest_id
          JOIN mapping.component_specs cs
            ON cs.production_orderline_id = (sp.single_product_json ->> 'production_orderline_id')::int
          WHERE b.batch_id = p_batch_id
          GROUP BY cs.production_date
        ) t
      ),
      '[]'::jsonb
    ),
    'internal_status', COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'internal_status_code', s.internal_status_code,
            'status_sequence', s.status_sequence,
            'amount', s.amount
          )
          ORDER BY s.status_sequence
        )
        FROM (
          SELECT
            n.nest_json ->> 'internal_status_code' AS internal_status_code,
            ist.sequence::int AS status_sequence,
            SUM(n.amount) AS amount
          FROM legacy.batch b
          JOIN legacy.nest n
            ON n.batch_uid = b.batch_uid
          JOIN mapping.internal_status ist
            ON ist.code = n.nest_json ->> 'internal_status_code'
          WHERE b.batch_id = p_batch_id
          GROUP BY n.nest_json ->> 'internal_status_code', ist.sequence
        ) s
      ),
      '[]'::jsonb
    )
  );
END;
$$;

alter function batch_info(integer) owner to xfw3;

