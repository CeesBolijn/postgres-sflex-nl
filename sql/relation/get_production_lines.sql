create function relation.get_production_lines() returns TABLE(models_json jsonb)
	stable
	language plpgsql
as $$
#variable_conflict use_column
BEGIN
    RETURN QUERY
    SELECT jsonb_agg(
      model_data || jsonb_build_object('production_lines', production_lines)
      ORDER BY model_code
    ) AS models_json
    FROM (
      SELECT
        line_json->'model'->>'code' AS model_code,
        (array_agg(line_json->'model' ORDER BY line_id))[1] AS model_data,
        jsonb_agg(
          jsonb_build_object(
            'production_line_id',   line_id,
            'code',                 line_json->>'code',
            'production_line_name', line_json->>'production_line_name',
            'block',                line_json->'block'
          )
          ORDER BY line_id
        ) AS production_lines
      FROM (
        SELECT line_id, line_json::jsonb AS line_json
        FROM relation.production_line
      ) pl
      WHERE line_json ? 'model'
      GROUP BY line_json->'model'->>'code'
    ) m;
END;
$$;

alter function relation.get_production_lines() owner to xfw3;

