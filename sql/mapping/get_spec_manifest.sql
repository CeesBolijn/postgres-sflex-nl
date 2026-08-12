create function get_spec_manifest(p_production_orderline_ids integer[]) returns TABLE(production_orderline_id integer, spec_manifest_json jsonb)
	stable
	language sql
as $$
    WITH codes AS (
        -- Options chosen on the sales orderline: match on the full key
        SELECT cs.production_orderline_id, ot.option_set, ot.option_code
        FROM mapping.component_specs cs
        JOIN mapping.sales_orderline_option soo
            ON soo.sales_orderline_id = cs.sales_orderline_id
        JOIN mapping.option_translation ot
            ON ot.parent_title_base  = soo.parent_title_base
            AND ot.option_title_base = soo.option_title_base
            AND (ot.api_code IS NULL OR ot.api_code = soo.api_code)
        WHERE cs.production_orderline_id = ANY(p_production_orderline_ids)

        UNION ALL

        -- Substrate material on the orderline
        SELECT cs.production_orderline_id, ot.option_set, ot.option_code
        FROM mapping.component_specs cs
        JOIN mapping.option_translation ot
            ON ot.material_id = cs.material_id
        WHERE cs.production_orderline_id = ANY(p_production_orderline_ids)

        UNION ALL

        -- Shipping flag on the orderline, only when actually shipping separately
        SELECT cs.production_orderline_id, ot.option_set, ot.option_code
        FROM mapping.component_specs cs
        JOIN mapping.option_translation ot
            ON ot.ship_separately = cs.ship_separately
        WHERE cs.production_orderline_id = ANY(p_production_orderline_ids)
          AND cs.ship_separately = true
    )
    SELECT
        c.production_orderline_id,
        jsonb_agg(DISTINCT jsonb_build_object(
            'option', c.option_set || '.' || c.option_code
        )) AS spec_manifest_json
    FROM codes c
    WHERE c.option_set  IS NOT NULL
      AND c.option_code IS NOT NULL
    GROUP BY c.production_orderline_id;
$$;

alter function get_spec_manifest(integer[]) owner to xfw3;

