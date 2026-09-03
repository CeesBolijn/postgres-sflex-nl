-- Impose resources: one row per unique site.material.width that has printers,
-- with the step level set to impose (dk.sheet.print.210.uv... -> dk.sheet.impose.210).
-- These rows are the lanes of the nest resource schedule: imposing happens per
-- material width, not per printer, and every printer of that width feeds it.
-- Derived, not hand-listed, so a new printer width brings its own impose row
-- on the next run. Idempotent: existing uids are left alone.
-- resource_json carries the chaining keys (docs/nest-planning-lane-items.md
-- §2.3): the next step may start after the first item, imposing itself takes
-- 900 seconds.

BEGIN;

WITH printer AS (
    -- levels: site.material.step.width.medium.brand.type.serial
    SELECT subpath(r.resource_path, 0, 1)::text AS site,
           subpath(r.resource_path, 1, 1)::text AS material,
           subpath(r.resource_path, 3, 1)::text AS width,
           r.line_id
    FROM relation.resource r
    WHERE r.resource_path ~ '*.print.*'
      AND nlevel(r.resource_path) >= 4
),
impose AS (
    -- min(): every group resolves to a single line today; a printer without a
    -- line_id does not drag the group to null
    SELECT p.site, p.material, p.width, min(p.line_id) AS line_id
    FROM printer p
    GROUP BY p.site, p.material, p.width
)
INSERT INTO relation.resource (resource_uid, resource_json, line_id, resource_path)
SELECT
    i.site || '-' || i.material || '-impose-' || i.width,
    jsonb_build_object(
        'name', 'Impose ' || i.material || ' ' || i.width,
        'step', 'impose',
        'next_start_after_first_item', 1,
        'next_start_lag_in_seconds', 900
    ),
    i.line_id,
    (i.site || '.' || i.material || '.impose.' || i.width)::ltree
FROM impose i
ON CONFLICT (resource_uid) DO NOTHING;

COMMIT;

-- expected: 17 rows — bh 6 (foil 160, non-adhesive 320/350, sheet 210/320,
-- textile 500), dk 11 (foil 060/160, label 033/051, non-adhesive 320/500,
-- paper 075, sheet 210/320, textile 320/500)
