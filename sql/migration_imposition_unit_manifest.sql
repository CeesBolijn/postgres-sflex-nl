-- Backfill and verification for legacy.imposition_unit_manifest.
-- See docs/imposition-unit-manifest.md for the proposal behind it.
--
-- Run first, in this order:
--   sql/legacy/imposition_unit_manifest.sql         (the table)
--   sql/legacy/create_imposition_unit_manifest.sql  (the rebuild function)
--   sql/legacy/crud_nest.sql                        (adds the PERFORM call)
--
-- Then this file. It only fills the recent window: 262 984 nests exist in
-- total, but the boards look at days, not years. Widen the interval if you
-- want more history — the function is idempotent, so re-running is free.

BEGIN;

-- Backfill the last 30 days (~40 500 nests). Chunked by day so one statement
-- never has to hold the whole set.
DO $$
DECLARE
    d date;
    v_nests bigint[];
BEGIN
    FOR d IN
        SELECT generate_series(current_date - 30, current_date, interval '1 day')::date
    LOOP
        SELECT array_agg(n.nest_id)
        INTO   v_nests
        FROM   legacy.nest n
        WHERE  (n.nested_at AT TIME ZONE 'Europe/Amsterdam')::date = d;

        IF v_nests IS NOT NULL THEN
            PERFORM legacy.create_imposition_unit_manifest(v_nests);
            RAISE NOTICE '% : % impositions', d, cardinality(v_nests);
        END IF;
    END LOOP;
END $$;

COMMIT;

-- ── verify ────────────────────────────────────────────────────────────

-- 1. coverage: impositions of the last 7 days with and without a manifest.
--    A nest without orderlines in legacy.single_product legitimately gets none.
SELECT count(*)                                        AS nests_last_7d,
       count(*) FILTER (WHERE mf.imposition_id IS NOT NULL) AS with_manifest,
       count(*) FILTER (WHERE mf.imposition_id IS NULL
                          AND sp.nest_id IS NOT NULL)  AS missing_but_has_orderlines
FROM legacy.nest n
LEFT JOIN LATERAL (SELECT 1 AS imposition_id FROM legacy.imposition_unit_manifest m
                   WHERE m.imposition_id = n.nest_id LIMIT 1) mf ON true
LEFT JOIN LATERAL (SELECT 1 AS nest_id FROM legacy.single_product sp2
                   WHERE sp2.nest_id = n.nest_id LIMIT 1) sp ON true
WHERE n.nested_at >= now() - interval '7 days';

-- 2. the four impositions of material 47 on today's board. Expected, from the
--    read-only dry run: 261 + 275 + 242 + 275 = 1053 s, so the board leaves the
--    900 s floor behind. Each imposition should carry exactly one line with an
--    impact — a sheet is printed once.
SELECT m.imposition_id,
       count(*)                                                AS manifest_rows,
       count(*) FILTER (WHERE m.production_impact_per_unit > 0) AS impact_lines,
       sum(m.production_impact_per_unit * m.amount)             AS impact_in_seconds
FROM legacy.imposition_unit_manifest m
WHERE m.imposition_id IN (2414708, 2415019, 2415024, 2415151)
GROUP BY m.imposition_id
ORDER BY m.imposition_id;

-- 2b. the lines that cost time, per imposition. Every row stores what it adds,
--     so the sum is the imposition's impact — see docs/formula-impact-per-step.md.
--     Until the subtraction rules and formula_level are in the xbom, two print
--     lines on one sheet each carry a full sheet pass and the sum reads high.
SELECT m.imposition_id,
       m.option_code,
       m.production_impact_per_unit,
       sum(m.production_impact_per_unit) OVER (PARTITION BY m.imposition_id) AS imposition_total
FROM legacy.imposition_unit_manifest m
JOIN legacy.nest n ON n.nest_id = m.imposition_id
WHERE m.production_impact_per_unit > 0
  AND n.nested_at >= now() - interval '2 days'
ORDER BY m.imposition_id, m.option_code
LIMIT 50;

-- 3. no orphans and no duplicates
SELECT (SELECT count(*) FROM legacy.imposition_unit_manifest m
        WHERE NOT EXISTS (SELECT 1 FROM legacy.nest n WHERE n.nest_id = m.imposition_id))
           AS orphan_rows,
       (SELECT count(*) FROM (
            SELECT imposition_id FROM legacy.imposition_unit_manifest
            WHERE production_impact_per_unit > 0
            GROUP BY 1 HAVING count(*) > 1) d)
           AS impositions_with_two_impact_lines;
