create function mapping.create_spec_unit_manifest(p_production_orderline_ids integer[]) returns TABLE(production_orderline_id integer, row_count bigint)
	language plpgsql
as $$
#variable_conflict use_column
BEGIN
    -- Resolve xbom rows for the given orderlines and rebuild their manifest.
    -- Delete-insert keeps the operation idempotent.
    DELETE FROM mapping.spec_unit_manifest m
    WHERE  m.production_orderline_id = ANY(p_production_orderline_ids);

    RETURN QUERY
    WITH orderline_codes AS (
        -- Option codes coming from the product/api mapping, per selected option
        SELECT cs.production_orderline_id,
               unnest(t.option_codes) AS option_code
        FROM   mapping.component_specs cs
        JOIN   mapping.sales_orderline_option slo
               ON slo.sales_orderline_id = cs.sales_orderline_id
        JOIN   mapping.option_translation t
               ON t.product_api_code = slo.product_api_code
              AND t.api_code         = slo.api_code
        WHERE  cs.production_orderline_id = ANY(p_production_orderline_ids)

        UNION

        -- Option codes coming from the material mapping, once per component
        SELECT cs.production_orderline_id,
               unnest(t.option_codes)
        FROM   mapping.component_specs cs
        JOIN   mapping.option_translation t
               ON t.material_id = cs.material_id
        WHERE  cs.production_orderline_id = ANY(p_production_orderline_ids)
    ),
    selected AS (
        SELECT   production_orderline_id,
                 array_agg(DISTINCT option_code) AS option_codes
        FROM     orderline_codes
        GROUP BY production_orderline_id
    ),
    matched AS (
        -- An xbom row applies when all parts of its composite code are selected
        SELECT s.production_orderline_id,
               x.xbom_id, x.option_code, x.item_code, x.scope,
               x.param_json, x.config_json,
               string_to_array(x.option_code, ';')              AS code_parts,
               cardinality(string_to_array(x.option_code, ';')) AS part_count
        FROM   selected s
        JOIN   catalog.xbom x
          ON   string_to_array(x.option_code, ';') <@ s.option_codes
        WHERE  x.status = 'active'
    ),
    filtered AS (
        -- A row is superseded only by a strictly more specific row covering the same parts
        SELECT m.*
        FROM   matched m
        WHERE  NOT EXISTS (
                   SELECT 1
                   FROM   matched m2
                   WHERE  m2.production_orderline_id = m.production_orderline_id
                     AND  m2.scope      = m.scope
                     AND  m2.code_parts @> m.code_parts
                     AND  m2.part_count > m.part_count
               )
    ),
    labeled AS (
        -- Snapshot the i18n label per xbom row; codes without an abb are skipped
        SELECT   f.production_orderline_id,
                 f.xbom_id,
                 f.option_code,
                 f.item_code,
                 f.scope,
                 f.param_json,
                 f.config_json,
                 jsonb_strip_nulls(jsonb_build_object(
                     'en', jsonb_build_object('abb',
                         string_agg(o.option_json -> 'i18n' -> 'en' ->> 'abb', ' ' ORDER BY p.pos)),
                     'nl', jsonb_build_object('abb',
                         string_agg(o.option_json -> 'i18n' -> 'nl' ->> 'abb', ' ' ORDER BY p.pos))
                 )) AS i18n
        FROM     filtered f
        CROSS    JOIN LATERAL unnest(f.code_parts) WITH ORDINALITY AS p(option_code, pos)
        LEFT     JOIN catalog.library_option o ON o.option_code = p.option_code
        GROUP BY f.production_orderline_id, f.xbom_id, f.option_code,
                 f.item_code, f.scope, f.param_json, f.config_json
    ),
    inserted AS (
        INSERT INTO mapping.spec_unit_manifest
               (production_orderline_id, option_code, item_code, scope,
                param_json, config_json, sort_order)
        SELECT l.production_orderline_id,
               l.option_code,
               l.item_code,
               l.scope,
               l.param_json,
               l.config_json || jsonb_build_object('i18n', l.i18n),
               l.xbom_id
        FROM   labeled l
        RETURNING production_orderline_id
    )
    SELECT   i.production_orderline_id,
             count(*) AS row_count
    FROM     inserted i
    GROUP BY i.production_orderline_id;
END;
$$;

alter function mapping.create_spec_unit_manifest(integer[]) owner to xfw3;

