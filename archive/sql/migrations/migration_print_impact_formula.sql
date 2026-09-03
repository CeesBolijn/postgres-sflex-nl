-- standard-print-impact versie 2: de snelheid komt uit het item, en neon telt
-- apart mee.
--
-- Versie 1 zette de snelheid zelf:
--
--     ["standard_print_speed_cm2_sec=222.22",
--      "production_impact_per_unit=width*height/standard_print_speed_cm2_sec"]
--
-- Dat gaf elke printmethode dezelfde 222,22 cm2/s, dus full-color en
-- full-color-white-white kwamen op hetzelfde uit. Nu draagt elk item zijn eigen
-- snelheid in item_json.params. mapping.create_spec_unit_manifest mengt de
-- numerieke keys van item_json -> 'params' al in de variabelen, dus de formule
-- hoeft niets op te halen.
--
-- WAAROM DE MAX, EN WAAROM NEON ERBUITEN VALT
--
-- Er kunnen meerdere printmethodes op een vel liggen en het vel gaat maar een
-- keer door de pers: de zwaarste methode dekt de rest. De impact van het vel is
-- dus de MAX over de methodes, niet de som.
--
-- Maar neon is een eigen inktgang die de max niet dekt. Ligt
-- full-color-white-white (1008,6 s) naast full-color-neon (825,2 s), dan geeft
-- een kale max 1008,6 - en is de neongang verdwenen, terwijl de pers hem wel
-- moet draaien. Daarom is de methode gesplitst in twee delen die elk hun eigen
-- max bijhouden en bij elkaar opgeteld worden:
--
--   standard_print_speed_cm2_sec   de fc- en witgangen samen
--   neon_speed_cm2_sec             de neongang
--
-- Voor het voorbeeld hierboven: max(1008,6; 275,1) + max(0; 550,2) = 1558,8 s,
-- precies fc + 2x wit + neon.
--
-- Neon krijgt een eigen max in plaats van "altijd optellen", zodat twee
-- neonmethodes op hetzelfde vel de neongang niet dubbel rekenen. En het staat
-- als snelheid in de params, niet als een vast verschil, zodat het met de
-- velmaat meebeweegt.
--
-- neon_speed_cm2_sec staat op alle elf items: 111,1 bij de drie neon-methodes
-- en 0 bij de rest. Die 0 is meteen de schakelaar - de evaluator kort de
-- ternary af, dus bij snelheid 0 wordt er niet gedeeld en komt er 0 uit. Een
-- aparte teller is niet nodig, want neon is altijd precies een gang. De key
-- moet wel op alle elf staan: zonder hem klapt de evaluatie op een onbekende
-- variabele.
--
-- Read-only nagerekend op vel 2415019 (203 x 301,1 cm):
--
--   fc                             275,1
--   fc-neon                        825,2
--   fc-2w-neon                    1558,8
--   fc-2w  + fc-neon      1008,6 +  550,2 = 1558,8
--   fc-neon + fc-2w        825,2 +  733,6 = 1558,8
--   fc-neon + fc-w-neon    825,2 +  367,0 = 1192,2   (geen dubbele neon)
--   alle elf, zwaar eerst 1099,3 + 550,2  = 1649,5
--   alle elf, licht eerst  elf bedragen   = 1649,5
--
-- De volgorde bepaalt alleen wie wat op zijn conto krijgt, niet het totaal.
-- print_impact en neon_impact beginnen op 0; een nieuwe methode is altijd
-- groter dan 0 en rekent dus vanzelf de eerste keer af.
--
-- formula_level blijft 1: het niveau hoort bij de code, niet bij de versie
-- (docs/catalog-formula.md). De snijformules op 2 en 3 blijven zoals ze zijn -
-- die hebben scope 'unit' en rekenen met de omtrek van het product.

BEGIN;

-- ── 1. de neongang uit de gecombineerde snelheid halen ────────────────
-- Alleen de drie neon-methodes veranderen: hun standard_print_speed_cm2_sec
-- gaat van de gecombineerde waarde naar alleen het fc/wit-deel.
--   full-color-neon              74,1 -> 222,2
--   full-color-white-neon        51,3 ->  95,2
--   full-color-white-white-neon  39,2 ->  60,6
UPDATE catalog.item i
SET item_json = jsonb_set(i.item_json, '{params,standard_print_speed_cm2_sec}',
                          to_jsonb(t.basis_speed))
FROM (VALUES
    ('PRINT-METHOD-FULL-COLOR-NEON',             222.2),
    ('PRINT-METHOD-FULL-COLOR-WHITE-NEON',        95.2),
    ('PRINT-METHOD-FULL-COLOR-WHITE-WHITE-NEON',  60.6)
) AS t(item_code, basis_speed)
WHERE i.item_code = t.item_code;

-- ── 2. neon_speed_cm2_sec op alle elf items ───────────────────────────
-- 40 m2/h = 111,1 cm2/s bij de drie neon-methodes, 0 bij de rest. Die 0 is
-- de schakelaar; zie de toelichting bovenaan.
UPDATE catalog.item i
SET item_json = i.item_json
                || jsonb_build_object('params',
                       (i.item_json -> 'params')
                       || jsonb_build_object('neon_speed_cm2_sec',
                              CASE WHEN i.item_code LIKE '%-NEON' THEN 111.1 ELSE 0 END))
WHERE i.item_group_code = 'print-method';


-- ── 3. de nieuwe formuleversie als draft ──────────────────────────────
-- formula_id is identity, dus niet meegeven.
INSERT INTO catalog.formula (formula_code, formula_json, formula_level, version, version_status)
SELECT 'standard-print-impact',
       jsonb_build_array(
           'print_impact_new = width * height / standard_print_speed_cm2_sec',
           'neon_impact_new = neon_speed_cm2_sec > 0 ? width * height / neon_speed_cm2_sec : 0',
           'production_impact_per_unit = (print_impact_new > print_impact ? print_impact_new - print_impact : 0) + (neon_impact_new > neon_impact ? neon_impact_new - neon_impact : 0)',
           'print_impact = print_impact_new > print_impact ? print_impact_new : print_impact',
           'neon_impact = neon_impact_new > neon_impact ? neon_impact_new : neon_impact'),
       1,
       coalesce(max(f.version), 0) + 1,
       'draft'
FROM catalog.formula f
WHERE f.formula_code = 'standard-print-impact';


-- ── 4. activeren ──────────────────────────────────────────────────────
-- De huidige actieve versie naar archived, de nieuwe naar active met
-- created_at = nu. Vanaf dat moment wint hij in get_formula, want die sorteert
-- op created_at desc, version desc. Versie 1 blijft staan, zodat
-- get_formula(p_at) voor een eerder moment nog de oude uitkomst geeft.
--
-- Wil je eerst alleen de draft, laat dit blok dan weg en draai het later.
UPDATE catalog.formula f
SET version_status = 'archived'
WHERE f.formula_code = 'standard-print-impact'
  AND f.version_status = 'active';

UPDATE catalog.formula f
SET version_status = 'active',
    created_at     = now()
WHERE f.formula_code = 'standard-print-impact'
  AND f.version_status = 'draft'
  AND f.version = (SELECT max(f2.version) FROM catalog.formula f2
                   WHERE f2.formula_code = 'standard-print-impact');

COMMIT;


-- ── verificatie ───────────────────────────────────────────────────────

-- 1. de params van de elf items. Verwacht: drie rijen met neon_speed 111,1 en
--    een basis-snelheid van 222,2 / 95,2 / 60,6; de rest neon_speed 0.
SELECT i.item_code,
       (i.item_json -> 'params' ->> 'standard_print_speed_cm2_sec')::numeric AS basis_speed,
       (i.item_json -> 'params' ->> 'neon_speed_cm2_sec')::numeric           AS neon_speed
FROM catalog.item i
WHERE i.item_group_code = 'print-method'
ORDER BY neon_speed DESC, basis_speed DESC;

-- 2. de versies van de code. Verwacht: v1 archived, v2 active.
--    Er is geen constraint die een tweede active tegenhoudt - alleen
--    unique (formula_code, version) - dus dit is de check die telt.
SELECT formula_id, version, version_status, formula_level, created_at
FROM catalog.formula
WHERE formula_code = 'standard-print-impact'
ORDER BY version;

-- 3. elke methode los op vel 2415019, dus met print_impact en neon_impact op 0.
--    Verwacht: fc 275,1 | fc-neon 825,2 | fc-2w 1008,6 | 4fc 1099,3 |
--              fc-2w-neon 1558,8
SELECT x.option_code,
       round((public.evaluate_many_nas(
           f.formula_json,
           jsonb_build_object('width', n.width, 'height', n.height,
                              'print_impact', 0, 'neon_impact', 0)
           || coalesce((SELECT jsonb_object_agg(e.key, e.value)
                        FROM jsonb_each(i.item_json -> 'params') e
                        WHERE jsonb_typeof(e.value) = 'number'), '{}'::jsonb)
       ) ->> 'production_impact_per_unit')::numeric, 1) AS impact
FROM catalog.xbom x
JOIN catalog.item i ON i.item_code = x.item_code
CROSS JOIN LATERAL catalog.get_formula(ARRAY[x.formula_code]) f
CROSS JOIN legacy.nest n
WHERE x.scope = 'imposition' AND x.version_status = 'active'
  AND x.formula_code = 'standard-print-impact'
  AND n.nest_id = 2415019
ORDER BY impact;

-- 4. het geval waar het om begonnen was: full-color-white-white naast
--    full-color-neon. Verwacht 1008,6 + 550,2 = 1558,8 in de ene volgorde en
--    825,2 + 733,6 = 1558,8 in de andere.
WITH f AS (SELECT formula_json FROM catalog.get_formula(ARRAY['standard-print-impact'])),
p AS (SELECT i.item_code,
             coalesce((SELECT jsonb_object_agg(e.key, e.value)
                       FROM jsonb_each(i.item_json -> 'params') e
                       WHERE jsonb_typeof(e.value) = 'number'), '{}'::jsonb) AS params
      FROM catalog.item i WHERE i.item_group_code = 'print-method'),
vel AS (SELECT jsonb_build_object('width', n.width, 'height', n.height,
                                  'print_impact', 0, 'neon_impact', 0) AS v
        FROM legacy.nest n WHERE n.nest_id = 2415019),
a1 AS (SELECT public.evaluate_many_nas(f.formula_json, vel.v || p.params) AS v
       FROM f, vel, p WHERE p.item_code = 'PRINT-METHOD-FULL-COLOR-WHITE-WHITE'),
a2 AS (SELECT public.evaluate_many_nas(f.formula_json, a1.v || p.params) AS v
       FROM f, a1, p WHERE p.item_code = 'PRINT-METHOD-FULL-COLOR-NEON'),
b1 AS (SELECT public.evaluate_many_nas(f.formula_json, vel.v || p.params) AS v
       FROM f, vel, p WHERE p.item_code = 'PRINT-METHOD-FULL-COLOR-NEON'),
b2 AS (SELECT public.evaluate_many_nas(f.formula_json, b1.v || p.params) AS v
       FROM f, b1, p WHERE p.item_code = 'PRINT-METHOD-FULL-COLOR-WHITE-WHITE')
SELECT volgorde, stap, methode,
       round((v ->> 'production_impact_per_unit')::numeric, 1) AS impact,
       round((v ->> 'print_impact')::numeric, 1)               AS print_impact,
       round((v ->> 'neon_impact')::numeric, 1)                AS neon_impact,
       sum(round((v ->> 'production_impact_per_unit')::numeric, 1))
           OVER (PARTITION BY volgorde) AS totaal
FROM (
    SELECT 'wit eerst'  AS volgorde, 1 AS stap, 'full-color-white-white' AS methode, v FROM a1
    UNION ALL SELECT 'wit eerst',  2, 'full-color-neon',        v FROM a2
    UNION ALL SELECT 'neon eerst', 1, 'full-color-neon',        v FROM b1
    UNION ALL SELECT 'neon eerst', 2, 'full-color-white-white', v FROM b2
) x
ORDER BY volgorde, stap;
