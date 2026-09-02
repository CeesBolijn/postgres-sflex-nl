drop function if exists mapping.create_spec_unit_manifest(integer[]);

create function mapping.create_spec_unit_manifest(p_production_orderline_ids integer[])
 RETURNS TABLE(production_orderline_id integer, row_count bigint)
 LANGUAGE plpgsql
AS $function$
#variable_conflict use_column
BEGIN
    -- Resolve xbom rows for the given orderlines and rebuild their manifest.
    -- Delete-insert keeps the operation idempotent.
    DELETE FROM mapping.spec_unit_manifest m
    WHERE  m.production_orderline_id = ANY(p_production_orderline_ids);

    RETURN QUERY
    WITH RECURSIVE orderline_codes AS (
        -- What the orderline actually selected: the api option itself, never
        -- the default (that is the fallback, resolved below)
        SELECT cs.production_orderline_id,
               unnest(t.option_codes) AS option_code
        FROM   mapping.component_specs cs
        JOIN   mapping.sales_orderline_option slo
               ON slo.sales_orderline_id = cs.sales_orderline_id
        JOIN   mapping.option_translation t
               ON t.product_api_code = slo.product_api_code
               AND t.api_code = slo.api_code
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
    -- The option set of a code, from the library instead of from its text.
    -- A code can sit in several sets (cutting-method.kiss-cut is in 57 and
    -- 103), so this is a set of ids per code, not one id.
    code_set AS (
        SELECT lo.option_code, array_agg(DISTINCT lo.option_set_id) AS set_ids
        FROM   catalog.library_option lo
        WHERE  lo.version_status = 'active'
          AND  lo.option_set_id IS NOT NULL
        GROUP  BY lo.option_code
    ),
    default_codes AS (
        -- A default is an override of last resort, not an extra option: it
        -- only applies when the orderline has nothing of that option set yet.
        -- Without this, choosing print-method.spot-color would leave
        -- print-method.full-color in the set as well, and the xbom would match
        -- on both.
        --
        -- The set comes from catalog.library_option, not from the text before
        -- the dot. Those are not the same thing: print-method is multi_select
        -- and its codes span sets 60, 87 and 108, so the old prefix test let a
        -- set-108 choice suppress a set-60 default — two different passes over
        -- the same sheet, one of them silently dropped. Composite codes
        -- (material.x;print-coverage.y) were mis-filed under the first part for
        -- the same reason. A code the library does not know falls back to its
        -- prefix, which is its own set.
        SELECT DISTINCT cs.production_orderline_id, c.option_code
        FROM   mapping.component_specs cs
        JOIN   mapping.sales_orderline_option slo
               ON slo.sales_orderline_id = cs.sales_orderline_id
        JOIN   mapping.option_translation t
               ON t.product_api_code = slo.product_api_code
               AND t.api_code = 'default'
        CROSS  JOIN LATERAL unnest(t.option_codes) AS c(option_code)
        LEFT   JOIN code_set dcs ON dcs.option_code = c.option_code
        WHERE  cs.production_orderline_id = ANY(p_production_orderline_ids)
          AND  NOT EXISTS (
                   SELECT 1
                   FROM   orderline_codes o
                   LEFT   JOIN code_set ocs ON ocs.option_code = o.option_code
                   WHERE  o.production_orderline_id = cs.production_orderline_id
                     AND  CASE
                              WHEN dcs.set_ids IS NOT NULL AND ocs.set_ids IS NOT NULL
                                  THEN dcs.set_ids && ocs.set_ids
                              ELSE split_part(o.option_code, '.', 1)
                                     = split_part(c.option_code, '.', 1)
                          END
               )
    ),
    selected AS (
        SELECT   production_orderline_id,
                 array_agg(DISTINCT option_code) AS option_codes
        FROM     (SELECT * FROM orderline_codes
                  UNION
                  SELECT * FROM default_codes) all_codes
        GROUP BY production_orderline_id
    ),
    matched AS (
        -- An xbom row applies when all parts of its composite code are selected
        SELECT s.production_orderline_id,
               x.xbom_id, x.option_code, x.item_code, x.scope,
               x.param_json, x.config_json, x.formula_code,
               string_to_array(x.option_code, ';')              AS code_parts,
               cardinality(string_to_array(x.option_code, ';')) AS part_count
        FROM   selected s
        JOIN   catalog.xbom x
          ON   string_to_array(x.option_code, ';') <@ s.option_codes
        WHERE  x.version_status = 'active'
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
                 f.formula_code,
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
                 f.item_code, f.scope, f.param_json, f.config_json, f.formula_code
    ),

    -- ── van hier af rekent de functie ────────────────────────────────
    -- De formule van elke regel, op zijn plek in de volgorde. catalog.get_formula
    -- levert de versie die nu geldt, gesorteerd op formula_level; binnen een
    -- level beslist xbom_id. Regels zonder formule krijgen rn ook, zodat ze
    -- gewoon meelopen in de keten.
    applying AS (
        SELECT gf.formula_code, gf.formula_json, gf.formula_level
        FROM   catalog.get_formula(
                   (SELECT array_agg(DISTINCT l.formula_code)
                    FROM labeled l WHERE l.formula_code IS NOT NULL)) gf
    ),
    row_formula AS (
        SELECT l.*, a.formula_json, a.formula_level,
               row_number() OVER (PARTITION BY l.production_orderline_id
                                  ORDER BY a.formula_level NULLS FIRST, l.xbom_id) AS rn,
               -- de constanten van deze regel: eerst het item, dan zijn params,
               -- dan de param_json van de xbom-regel. Alleen getallen, want
               -- evaluate_many_nas weigert tekst.
               coalesce((SELECT jsonb_object_agg(e.key, e.value)
                         FROM jsonb_each(ci.item_json) e
                         WHERE jsonb_typeof(e.value) = 'number'), '{}'::jsonb)
               || coalesce((SELECT jsonb_object_agg(e.key, e.value)
                            FROM jsonb_each(ci.item_json -> 'params') e
                            WHERE jsonb_typeof(e.value) = 'number'), '{}'::jsonb)
               || coalesce((SELECT jsonb_object_agg(e.key, e.value)
                            FROM jsonb_each(l.param_json) e
                            WHERE jsonb_typeof(e.value) = 'number'), '{}'::jsonb)
                   AS row_params
        FROM   labeled l
        LEFT   JOIN applying a ON a.formula_code = l.formula_code
        LEFT   JOIN catalog.item ci ON ci.item_code = l.item_code
    ),
    -- De startwaarden per orderregel. De maten van de spec, amount 1 (de kolom
    -- is per unit), en 0 voor ELKE naam die links van een = staat in een van de
    -- formules die straks draaien.
    --
    -- Dat laatste is nodig omdat de evaluator op een onbekende variabele niet 0
    -- teruggeeft maar de hele aanroep laat klappen. Een accumulator als
    -- print_impact wordt altijd toegekend door de formule die hem ook leest, dus
    -- de linkerkant afsnijden vangt ze allemaal - zonder een lijstje in de code.
    seed AS (
        SELECT rf.production_orderline_id,
               jsonb_build_object(
                   'width',  coalesce(cs.product_width, 0),
                   'height', coalesce(cs.product_height, 0),
                   'amount', 1)
               || coalesce((SELECT jsonb_object_agg(trim(split_part(ln.value, '=', 1)), 0)
                            FROM   row_formula rf2
                            CROSS  JOIN LATERAL jsonb_array_elements_text(rf2.formula_json) ln
                            WHERE  rf2.production_orderline_id = rf.production_orderline_id),
                           '{}'::jsonb) AS vars
        FROM   (SELECT DISTINCT production_orderline_id FROM row_formula) rf
        LEFT   JOIN mapping.component_specs cs
               ON cs.production_orderline_id = rf.production_orderline_id
    ),
    -- De keten: regel voor regel, de variabelen gaan mee. Een regel zonder
    -- formule laat de ruimte ongemoeid en zet alleen zijn eigen uitkomst op 0,
    -- zodat de vorige regel niet in deze blijft staan.
    fold AS (
        SELECT rf.production_orderline_id, rf.rn, rf.xbom_id,
               CASE WHEN rf.formula_json IS NULL
                    THEN s.vars || jsonb_build_object('production_impact_per_unit', 0)
                    ELSE public.evaluate_many_nas(rf.formula_json, s.vars || rf.row_params)
               END AS vars
        FROM   row_formula rf
        JOIN   seed s ON s.production_orderline_id = rf.production_orderline_id
        WHERE  rf.rn = 1

        UNION ALL

        SELECT rf.production_orderline_id, rf.rn, rf.xbom_id,
               CASE WHEN rf.formula_json IS NULL
                    THEN f.vars || jsonb_build_object('production_impact_per_unit', 0)
                    ELSE public.evaluate_many_nas(rf.formula_json, f.vars || rf.row_params)
               END
        FROM   fold f
        JOIN   row_formula rf
               ON rf.production_orderline_id = f.production_orderline_id
              AND rf.rn = f.rn + 1
    ),
    inserted AS (
        -- Een variabele met de naam van een kolom gaat naar die kolom; de rest
        -- blijft waar hij was. Dit zijn de numerieke kolommen van
        -- mapping.spec_unit_manifest - komt er een bij, dan komt hier een regel
        -- bij. De evaluator levert alleen getallen, dus jsonb-kolommen kunnen
        -- op deze manier niet geraakt worden.
        INSERT INTO mapping.spec_unit_manifest
               (production_orderline_id, option_code, item_code, scope,
                param_json, config_json, sort_order, production_impact_per_unit, price)
        SELECT rf.production_orderline_id,
               rf.option_code,
               rf.item_code,
               rf.scope,
               rf.param_json,
               rf.config_json || jsonb_build_object('i18n', rf.i18n),
               coalesce(round((fd.vars ->> 'sort_order')::numeric)::integer, rf.xbom_id),
               coalesce(round((fd.vars ->> 'production_impact_per_unit')::numeric)::integer, 0),
               coalesce((fd.vars ->> 'price')::numeric, 0)
        FROM   row_formula rf
        JOIN   fold fd ON fd.production_orderline_id = rf.production_orderline_id
                      AND fd.rn = rf.rn
        RETURNING production_orderline_id
    )
    SELECT   i.production_orderline_id,
             count(*) AS row_count
    FROM     inserted i
    GROUP BY i.production_orderline_id;

    -- the manifest also travels on the spec row itself, written in the
    -- same pass so table and column can never disagree; the aggregation
    -- lives in one place and can be re-run retroactively on its own
    PERFORM mapping.update_component_specs_manifest(p_production_orderline_ids);
END;
$function$;

alter function mapping.create_spec_unit_manifest(p_production_orderline_ids integer[]) owner to xfw3;
