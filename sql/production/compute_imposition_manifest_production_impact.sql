create function production.compute_imposition_manifest_production_impact(p_imposition_id bigint, p_item_code text, p_overhead_fixed integer DEFAULT 0, p_overhead_factor numeric DEFAULT 0) returns integer
	stable
	language sql
as $$
    WITH per_spec AS (
        SELECT spec_id,
               SUM(production_impact_per_unit) AS impact_per_unit
          FROM job.spec_unit_manifest
         WHERE item_code = p_item_code
         GROUP BY spec_id
    ),
    imposition_specs AS (
        SELECT el.spec_id,
               jsonb_array_length(el.placement) AS amount
          FROM production.imposition i
         CROSS JOIN LATERAL jsonb_to_recordset(i.placement_json -> 'specs')
                            AS el(spec_id BIGINT, placement JSONB)
         WHERE i.imposition_id = p_imposition_id
    )
    SELECT COALESCE(
               SUM(is_.amount * ps.impact_per_unit * (1 + p_overhead_factor) + p_overhead_fixed),
               0
           )::INTEGER
      FROM imposition_specs is_
      JOIN per_spec ps ON ps.spec_id = is_.spec_id;
$$;

alter function production.compute_imposition_manifest_production_impact(bigint, text, integer, numeric) owner to xfw3;

