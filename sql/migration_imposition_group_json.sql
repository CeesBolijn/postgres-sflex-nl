-- catalog.imposition_group gets one json column, named after its table the
-- way resource_json and line_json are. Its first tenant is the waste table:
-- how much of a format is lost when this group is imposed on it. Waste
-- depends on format and group, not on the machine — the machine side lives in
-- production.resource_setting.
--
-- Nothing here is invented. The formats come from
-- mapping.material_production_line.line_json -> 'specs' of the group's
-- material (imposition_group_id is an alias of material_id for now), and the
-- factor is the measured average of legacy.nest over the last 180 days:
-- nest_json carries material_id, material_width, material_height and
-- waste_percentage on every nest.
--
-- waste_factor is a fraction, not a percentage: gross = net * (1 + factor),
-- so a formula never has to divide by 100.

BEGIN;

ALTER TABLE catalog.imposition_group
    ADD COLUMN IF NOT EXISTS imposition_group_json jsonb DEFAULT '{}'::jsonb NOT NULL;

COMMENT ON COLUMN catalog.imposition_group.imposition_group_json IS
    'Properties of the group itself. waste: one entry per format (width exact, first max_height that fits), waste_factor as a fraction, measured from legacy.nest.';

WITH nest AS (
    -- one row per imposition actually made; negative and 100% values are
    -- data errors (the tail runs to -3739), so they stay out of the average
    SELECT (n.nest_json ->> 'material_id')::integer      AS material_id,
           (n.nest_json ->> 'material_width')::numeric   AS width,
           (n.nest_json ->> 'material_height')::numeric  AS height,
           (n.nest_json ->> 'waste_percentage')::numeric AS waste_percentage
    FROM legacy.nest n
    WHERE n.nested_at > now() - interval '180 days'
      AND n.nest_json ? 'material_width'
      AND (n.nest_json ->> 'waste_percentage')::numeric >= 0
      AND (n.nest_json ->> 'waste_percentage')::numeric < 100
      AND (n.nest_json ->> 'material_width')::numeric > 0
),
fallback AS (
    SELECT round(avg(waste_percentage) / 100, 3) AS waste_factor FROM nest
),
imposable AS (
    -- only sheet (1) and roll (3) are imposed; piece and typeless materials
    -- have no imposition group, so they get no formats either
    SELECT DISTINCT m.material_id
    FROM mapping.material_production_line m
    WHERE m.line_json ->> 'material_media_type_id' IN ('1', '3')
),
spec_format AS (
    SELECT DISTINCT
           g.imposition_group_id,
           m.material_id,
           (s.value ->> 'width')::numeric      AS width,
           (s.value ->> 'max_height')::numeric AS max_height
    FROM catalog.imposition_group g
    JOIN imposable im ON im.material_id = g.imposition_group_id
    JOIN mapping.material_production_line m
      ON m.material_id = g.imposition_group_id  -- alias: group id = material id
    CROSS JOIN LATERAL jsonb_array_elements(coalesce(m.line_json -> 'specs', '[]'::jsonb)) s
    WHERE s.value ? 'width' AND s.value ? 'max_height'
),
format AS (
    -- every distinct format of the group's material, over all its lines, with
    -- the bracket below it: an entry covers heights up to its own max_height
    -- and above the previous one
    SELECT f.*,
           lag(f.max_height) OVER (PARTITION BY f.imposition_group_id, f.width
                                   ORDER BY f.max_height) AS prev_max_height
    FROM (
        SELECT * FROM spec_format
        UNION
        -- Materials without registered specs still get their formats, taken
        -- from what was actually imposed. Forex Budget and Polystyreen are
        -- planned daily but carry no specs, and a board row without a format
        -- cannot compute a duration at all.
        SELECT g.imposition_group_id, n.material_id, n.width, max(n.height) AS max_height
        FROM catalog.imposition_group g
        JOIN imposable im ON im.material_id = g.imposition_group_id
        JOIN nest n ON n.material_id = g.imposition_group_id
        WHERE NOT EXISTS (SELECT 1 FROM spec_format sf
                          WHERE sf.imposition_group_id = g.imposition_group_id)
        GROUP BY g.imposition_group_id, n.material_id, n.width
    ) f
),
-- one pass per level instead of correlated subqueries per format:
-- with 479 formats over 246k nests the correlated form would scan the nest
-- set nearly two thousand times
by_bracket AS (
    SELECT f.imposition_group_id, f.width, f.max_height,
           round(avg(n.waste_percentage) / 100, 3) AS waste_factor,
           round(percentile_cont(0.5) WITHIN GROUP (
               ORDER BY n.width * n.height / 10000.0)::numeric, 2) AS imposition_sqm
    FROM format f
    JOIN nest n ON n.material_id = f.material_id
               AND n.width = f.width
               AND n.height <= f.max_height
               AND (f.prev_max_height IS NULL OR n.height > f.prev_max_height)
    GROUP BY f.imposition_group_id, f.width, f.max_height
),
by_width AS (
    SELECT n.material_id, n.width,
           round(avg(n.waste_percentage) / 100, 3) AS waste_factor,
           round(percentile_cont(0.5) WITHIN GROUP (
               ORDER BY n.width * n.height / 10000.0)::numeric, 2) AS imposition_sqm
    FROM nest n
    GROUP BY n.material_id, n.width
),
measured AS (
    -- the bracket itself, else everything of that width, else the overall
    -- average: a format without history still gets a number
    SELECT f.imposition_group_id, f.width, f.max_height,
           coalesce(b.waste_factor, w.waste_factor, (SELECT waste_factor FROM fallback)) AS waste_factor,
           coalesce(b.imposition_sqm, w.imposition_sqm,
                    round(f.width * f.max_height / 10000.0, 2))                          AS imposition_sqm
    FROM format f
    LEFT JOIN by_bracket b ON b.imposition_group_id = f.imposition_group_id
                          AND b.width = f.width AND b.max_height = f.max_height
    LEFT JOIN by_width  w ON w.material_id = f.material_id AND w.width = f.width
),
waste AS (
    SELECT m.imposition_group_id,
           jsonb_agg(jsonb_build_object('width', m.width,
                                        'max_height', m.max_height,
                                        'waste_factor', m.waste_factor,
                                        'imposition_sqm', m.imposition_sqm)
                     ORDER BY m.width, m.max_height) AS waste_json
    FROM measured m
    GROUP BY m.imposition_group_id
)
UPDATE catalog.imposition_group g
SET imposition_group_json = g.imposition_group_json || jsonb_build_object('waste', w.waste_json)
FROM waste w
WHERE w.imposition_group_id = g.imposition_group_id;

-- the complete specs travel with the item as well, so a price or formula can
-- read the format without joining back to the material
WITH item_specs AS (
    SELECT i.item_id,
           jsonb_agg(DISTINCT s.value) AS specs
    FROM catalog.item i
    JOIN catalog.imposition_group g ON g.item_code_paths @> array[i.item_code_path]
    JOIN mapping.material_production_line m ON m.material_id = g.imposition_group_id
    CROSS JOIN LATERAL jsonb_array_elements(coalesce(m.line_json -> 'specs', '[]'::jsonb)) s
    GROUP BY i.item_id
)
UPDATE catalog.item i
SET item_json = coalesce(i.item_json, '{}'::jsonb) || jsonb_build_object('specs', s.specs)
FROM item_specs s
WHERE s.item_id = i.item_id
  AND coalesce(i.item_json -> 'specs', '[]'::jsonb) IS DISTINCT FROM s.specs;

COMMIT;

-- expected after the material specs were completed: 398 groups get a waste
-- list (479 formats) and 401 items get their specs — up from 149/227/149.
-- Measured over ~246 000 usable nests: average waste 21.07%, median 16.48%,
-- so the hard-coded 20 the functions carried sits right between them.
-- 40 specs still have no max_height (media type 2 "piece" and 3 rows without
-- a type); those formats stay out until their bracket is known.
