-- Rebuild the manifest of the given impositions straight from the xbom. Same
-- delete-insert shape as mapping.create_spec_unit_manifest, so calling it twice
-- is calling it once. Set-based, no loop.
--
-- The chain, and why it runs this way:
--   1. the orderlines on the imposition (legacy.single_product) only serve to
--      find the option codes; nothing per-orderline survives into the manifest
--   2. per orderline the codes resolve exactly as in
--      mapping.create_spec_unit_manifest: the api options, the material
--      mapping, and a default only where that option set is still empty
--   3. catalog.get_xbom_grouping_keys turns those codes into the grouping key
--      of the 'imposition' scope — the codes that actually drive an xbom line
--   4. the manifest rows are the active scope 'imposition' xbom lines of that
--      key, evaluated against the sheet: legacy.nest.width and .height, in
--      centimetres, and .amount
--
-- print-method and cutting-method are multi_select in catalog.library_option,
-- so one imposition can legitimately carry several method lines — each is a
-- pass over the sheet. They are kept, not collapsed: the manifest is a list of
-- passes and the consumer sums production_impact_per_unit * amount over the
-- rows. Codes of a single-select set can never produce two rows, because the
-- resolution keeps at most one per set.
--
-- Every row stores what it adds, and the reader only ever sums — see
-- docs/formula-impact-per-step.md. A later formula_level subtracts what the
-- earlier levels already stored, so nested print-method totals (fc, fc-w,
-- fc-2w) never count twice. Today that is not in place yet: all 11
-- formula-bearing lines share standard-print-impact with an empty param_json,
-- so two print lines on one sheet still charge the full sheet twice.
drop function if exists legacy.create_imposition_unit_manifest(bigint[]);

create function legacy.create_imposition_unit_manifest(p_imposition_ids bigint[])
	returns TABLE(imposition_id bigint, row_count bigint)
	language plpgsql
as $$
#variable_conflict use_column
BEGIN
    DELETE FROM legacy.imposition_unit_manifest m
    WHERE m.imposition_id = ANY (p_imposition_ids);

    RETURN QUERY
    WITH ol AS (
        SELECT DISTINCT sp.nest_id::bigint AS imposition_id,
               sp.production_orderline_id
        FROM legacy.single_product sp
        WHERE sp.nest_id = ANY (p_imposition_ids)
          AND sp.production_orderline_id IS NOT NULL
    ),
    orderline_codes AS (
        -- what the orderline selected, plus what its material maps to
        SELECT o.production_orderline_id, unnest(t.option_codes) AS option_code
        FROM ol o
        JOIN mapping.component_specs cs ON cs.production_orderline_id = o.production_orderline_id
        JOIN mapping.sales_orderline_option slo ON slo.sales_orderline_id = cs.sales_orderline_id
        JOIN mapping.option_translation t
             ON t.product_api_code = slo.product_api_code AND t.api_code = slo.api_code
        UNION
        SELECT o.production_orderline_id, unnest(t.option_codes)
        FROM ol o
        JOIN mapping.component_specs cs ON cs.production_orderline_id = o.production_orderline_id
        JOIN mapping.option_translation t ON t.material_id = cs.material_id
    ),
    default_codes AS (
        -- a default is an override of last resort: only where the orderline
        -- has nothing of that option set yet
        SELECT DISTINCT o.production_orderline_id, c.option_code
        FROM ol o
        JOIN mapping.component_specs cs ON cs.production_orderline_id = o.production_orderline_id
        JOIN mapping.sales_orderline_option slo ON slo.sales_orderline_id = cs.sales_orderline_id
        JOIN mapping.option_translation t
             ON t.product_api_code = slo.product_api_code AND t.api_code = 'default'
        CROSS JOIN LATERAL unnest(t.option_codes) AS c(option_code)
        WHERE NOT EXISTS (
                  SELECT 1 FROM orderline_codes oc
                  WHERE oc.production_orderline_id = o.production_orderline_id
                    AND split_part(oc.option_code, '.', 1) = split_part(c.option_code, '.', 1))
    ),
    selected AS (
        SELECT production_orderline_id, array_agg(DISTINCT option_code) AS option_codes
        FROM (SELECT * FROM orderline_codes UNION SELECT * FROM default_codes) a
        GROUP BY production_orderline_id
    ),
    -- the grouping key of the imposition scope, per imposition
    key_code AS (
        SELECT DISTINCT o.imposition_id, c.option_code
        FROM ol o
        JOIN selected s ON s.production_orderline_id = o.production_orderline_id
        CROSS JOIN LATERAL catalog.get_xbom_grouping_keys(s.option_codes) g
        CROSS JOIN LATERAL unnest(g.grouping_key) AS c(option_code)
        WHERE g.scope = 'imposition'
    ),
    -- every matching xbom line, evaluated against the sheet
    line AS (
        SELECT k.imposition_id, x.xbom_id, x.option_code, x.item_code,
               n.amount,
               x.param_json
                   || jsonb_build_object('width',  n.width,
                                         'height', n.height,
                                         'amount', n.amount) AS param_json,
               x.config_json,
               coalesce(x.sort_order, 0) AS sort_order,
               coalesce(imp.production_impact_per_unit, 0) AS production_impact_per_unit
        FROM key_code k
        JOIN legacy.nest n ON n.nest_id = k.imposition_id
        JOIN catalog.xbom x
          ON x.option_code = k.option_code
         AND x.scope = 'imposition'
         AND x.version_status = 'active'
        LEFT JOIN LATERAL (
            SELECT cf.formula_json
            FROM catalog.formula cf
            WHERE cf.formula_code = x.formula_code
              AND cf.version_status = 'active'
            ORDER BY cf.version DESC
            LIMIT 1
        ) cf ON true
        LEFT JOIN LATERAL (
            -- the sheet is the unit here: width x height of the nest, in
            -- centimetres, with the xbom row's own constants underneath
            SELECT round((public.evaluate_many_nas(
                       cf.formula_json,
                       coalesce((SELECT jsonb_object_agg(e.key, e.value)
                                 FROM jsonb_each(x.param_json) e
                                 WHERE jsonb_typeof(e.value) = 'number'), '{}'::jsonb)
                       || jsonb_build_object('width',  coalesce(n.width, 0),
                                             'height', coalesce(n.height, 0),
                                             'amount', coalesce(n.amount, 1))
                   ) ->> 'production_impact_per_unit')::numeric)::integer
                   AS production_impact_per_unit
            WHERE cf.formula_json IS NOT NULL
        ) imp ON true
    ),
    inserted AS (
        INSERT INTO legacy.imposition_unit_manifest
            (imposition_id, xbom_id, option_code, item_code, amount,
             param_json, config_json, production_impact_per_unit, sort_order)
        SELECT l.imposition_id, l.xbom_id, l.option_code, l.item_code, l.amount,
               l.param_json, l.config_json, l.production_impact_per_unit, l.sort_order
        FROM line l
        ON CONFLICT ON CONSTRAINT imposition_unit_manifest_uq DO UPDATE
            SET xbom_id                    = EXCLUDED.xbom_id,
                item_code                  = EXCLUDED.item_code,
                amount                     = EXCLUDED.amount,
                param_json                 = EXCLUDED.param_json,
                config_json                = EXCLUDED.config_json,
                production_impact_per_unit = EXCLUDED.production_impact_per_unit,
                sort_order                 = EXCLUDED.sort_order,
                updated_at                 = now()
        RETURNING imposition_id
    )
    SELECT i.imposition_id, count(*) AS row_count
    FROM inserted i
    GROUP BY i.imposition_id;
END;
$$;

alter function legacy.create_imposition_unit_manifest(bigint[]) owner to xfw3;
