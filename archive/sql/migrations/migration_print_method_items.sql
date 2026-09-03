-- Een catalog.item per printmethode, met de getotaliseerde persnelheid in
-- item_json.params.standard_print_speed_cm2_sec.
--
-- "Getotaliseerd" wil zeggen: de snelheid geldt voor de hele methode, niet per
-- gang. full-color is een gang op 80 m2/h = 222,22 cm2/s; full-color-full-color
-- zijn twee gangen en staat dus op de helft, 111,11 cm2/s. De impact is daarmee
-- altijd dezelfde deling, ongeacht de code:
--
--     production_impact_per_unit = width * height / standard_print_speed_cm2_sec
--
-- De basissnelheden: fc 80 m2/h, w 60 m2/h, neon 40 m2/h. Omgerekend naar
-- cm2/s en samengesteld volgens 1/v = som(gangen / gangsnelheid):
--
--     v = 2000 / (9 * fc + 12 * w + 18 * neon)
--
-- mapping.create_spec_unit_manifest leest de numerieke keys van
-- item_json -> 'params' al mee in de evaluatie, dus de formule hoeft de
-- snelheid niet zelf op te halen.
--
-- item_id en item_group_id zijn identity, item_code_path leidt zichzelf af uit
-- item_code (text2ltree(replace(lower(item_code), '-', '.'))).

BEGIN;

-- ── de itemgroep ──────────────────────────────────────────────────────
-- catalog.item.item_group_code heeft een foreign key naar deze tabel, en
-- 'material' was tot nu toe de enige groep.
--
-- possible_status_sequence bepaalt straks de stap: 700 is 'print' in
-- relation.lookup 'lookup_step_category'. CONTROLEER DIT - het is de enige
-- waarde in dit script die ik niet uit bestaande data heb kunnen aflezen.
INSERT INTO catalog.item_group (item_group_code, item_group_json, possible_status_sequence)
VALUES ('print-method', jsonb_build_object('sort_order', 10), '[[700]]'::jsonb)
ON CONFLICT (item_group_code) DO UPDATE
    SET item_group_json          = EXCLUDED.item_group_json,
        possible_status_sequence = EXCLUDED.possible_status_sequence,
        updated_at               = now();


-- ── de elf items ──────────────────────────────────────────────────────
-- item_code volgt de option_code een op een, zodat item_code_path netjes
-- onder print.method.* uitkomt.
INSERT INTO catalog.item (item_code, item_group_code, description, item_json)
SELECT t.item_code, 'print-method', t.description,
       jsonb_build_object(
           'params', jsonb_build_object(
               'standard_print_speed_cm2_sec',
               round(2000.0 / (9 * t.fc + 12 * t.w + 18 * t.neon), 4)),
           'passes', jsonb_build_object('fc', t.fc, 'w', t.w, 'neon', t.neon),
           'option_code', 'print-method.' || t.option_code)
FROM (VALUES
    ('PRINT-METHOD-FULL-COLOR',
     'full-color',                                  'Full colour',                            1, 0, 0),
    ('PRINT-METHOD-FULL-COLOR-FULL-COLOR',
     'full-color-full-color',                       '2x full colour',                         2, 0, 0),
    ('PRINT-METHOD-FULL-COLOR-FULL-COLOR-FULL-COLOR-FULL-COLOR',
     'full-color-full-color-full-color-full-color', '4x full colour',                         4, 0, 0),
    ('PRINT-METHOD-FULL-COLOR-NEON',
     'full-color-neon',                             'Full colour + neon',                     1, 0, 1),
    ('PRINT-METHOD-FULL-COLOR-WHITE',
     'full-color-white',                            'Full colour + wit',                      1, 1, 0),
    ('PRINT-METHOD-FULL-COLOR-WHITE-FULL-COLOR',
     'full-color-white-full-color',                 'Full colour + wit + full colour',        2, 1, 0),
    ('PRINT-METHOD-FULL-COLOR-WHITE-NEON',
     'full-color-white-neon',                       'Full colour + wit + neon',               1, 1, 1),
    ('PRINT-METHOD-FULL-COLOR-WHITE-WHITE',
     'full-color-white-white',                      'Full colour + 2x wit',                   1, 2, 0),
    ('PRINT-METHOD-FULL-COLOR-WHITE-WHITE-NEON',
     'full-color-white-white-neon',                 'Full colour + 2x wit + neon',            1, 2, 1),
    ('PRINT-METHOD-WHITE',
     'white',                                       'Wit',                                    0, 1, 0),
    ('PRINT-METHOD-WHITE-WHITE',
     'white-white',                                 '2x wit',                                 0, 2, 0)
) AS t(item_code, option_code, description, fc, w, neon)
ON CONFLICT (item_code) DO UPDATE
    SET item_group_code = EXCLUDED.item_group_code,
        description     = EXCLUDED.description,
        item_json       = EXCLUDED.item_json;


-- ── de xbom-regels naar hun item wijzen ───────────────────────────────
-- De elf imposition-regels met een formule hebben nu item_code null, waardoor
-- er geen weg is van de manifestregel naar het item (en dus naar de stap).
UPDATE catalog.xbom x
SET item_code = 'PRINT-METHOD-' || upper(split_part(x.option_code, '.', 2))
WHERE x.scope = 'imposition'
  AND x.version_status = 'active'
  AND x.option_code LIKE 'print-method.%'
  AND x.item_code IS NULL
  AND EXISTS (SELECT 1 FROM catalog.item i
              WHERE i.item_code = 'PRINT-METHOD-' || upper(split_part(x.option_code, '.', 2)));

COMMIT;


-- ── verificatie ───────────────────────────────────────────────────────

-- 1. de elf items met hun snelheid en het aantal gangen
SELECT i.item_code, i.item_code_path::text,
       (i.item_json -> 'params' ->> 'standard_print_speed_cm2_sec')::numeric AS speed_cm2_sec,
       i.item_json -> 'passes' AS passes
FROM catalog.item i
WHERE i.item_group_code = 'print-method'
ORDER BY speed_cm2_sec DESC;

-- 2. de impact van vel 2415019 (203 x 301,1 cm) per methode.
--    Verwacht, gelijk aan sql/test_impact_formulas.sql:
--      full-color                  275,1 s
--      full-color-white-white     1008,5 s
--      4x full-color              1100,2 s
--      full-color-white-white-neon 1558,6 s
SELECT i.item_code,
       (i.item_json -> 'params' ->> 'standard_print_speed_cm2_sec')::numeric AS speed_cm2_sec,
       round((n.width * n.height
              / (i.item_json -> 'params' ->> 'standard_print_speed_cm2_sec')::numeric), 1) AS impact
FROM catalog.item i
CROSS JOIN legacy.nest n
WHERE i.item_group_code = 'print-method' AND n.nest_id = 2415019
ORDER BY impact;

-- 3. de xbom-regels die nu een item hebben (verwacht: 11, geen null meer)
SELECT x.option_code, x.item_code, x.formula_code
FROM catalog.xbom x
WHERE x.scope = 'imposition' AND x.version_status = 'active'
  AND x.option_code LIKE 'print-method.%'
ORDER BY x.option_code;
