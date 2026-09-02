-- ============================================================
-- catalog.item.item_json: weight and thickness move from the specs to
-- item_json.params.
--
-- Why: a spec entry is a FORMAT (width, height, min/max height, article
-- code) — weight and thickness do not depend on the format, they are
-- absolute properties of the material. Repeating them per format made them
-- look format-bound and left gaps: six items carry the thickness on some
-- specs and not on others. In params they are stated once, and the impact
-- formulas can read them as variables (same shape as the configurator's
-- param_json.params).
--
--   { "specs": [{ "width": 58, "height": 10000, "min_height": 100, ... }],
--     "params": { "weight": 0.3, "thickness": 0.35 },
--     "media_type": "roll", "material_id": 103 }
--
-- Lossless, verified on the data (26 aug): 401 items with specs, every one
-- has a single weight and a single thickness across its specs (0 items with
-- two different values), all values are json numbers. The six items with a
-- partial thickness get the one value they have.
--
-- Idempotent: an item whose specs no longer carry the keys is not touched,
-- and an existing params object is merged, not replaced.
-- ============================================================

BEGIN;

WITH item_params AS (
    -- one weight and one thickness per item: the values are uniform, so
    -- min() picks the value wherever a spec states it
    SELECT i.item_code,
           jsonb_strip_nulls(jsonb_build_object(
               'weight',    min((s.value ->> 'weight')::numeric),
               'thickness', min((s.value ->> 'thickness')::numeric))) AS params,
           jsonb_agg(s.value - 'weight' - 'thickness' ORDER BY s.ord)  AS specs
    FROM   catalog.item i
    CROSS  JOIN LATERAL jsonb_array_elements(i.item_json -> 'specs')
                        WITH ORDINALITY AS s(value, ord)
    WHERE  i.item_json ? 'specs'
    GROUP  BY i.item_code
    HAVING bool_or(s.value ? 'weight' OR s.value ? 'thickness')
)
UPDATE catalog.item i
SET    item_json = jsonb_set(i.item_json, '{specs}', p.specs)
                   || jsonb_build_object('params',
                          coalesce(i.item_json -> 'params', '{}'::jsonb) || p.params)
FROM   item_params p
WHERE  p.item_code = i.item_code;

-- verify: no spec carries the keys any more, and every item that had them
-- now has them in params
SELECT count(*)                                                         AS items_with_specs,
       count(*) FILTER (WHERE item_json ? 'params')                     AS with_params,
       count(*) FILTER (WHERE item_json #> '{params,weight}' IS NOT NULL)    AS with_weight,
       count(*) FILTER (WHERE item_json #> '{params,thickness}' IS NOT NULL) AS with_thickness,
       count(*) FILTER (WHERE EXISTS (
           SELECT 1 FROM jsonb_array_elements(item_json -> 'specs') s
           WHERE  s.value ? 'weight' OR s.value ? 'thickness'))         AS specs_still_carrying
FROM   catalog.item
WHERE  item_json ? 'specs';
-- expected: 401 / 401 / 401 / 142 / 0

COMMIT;
