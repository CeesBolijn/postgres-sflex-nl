-- mock.material_resource_plan becomes mock.material_impose_plan, and its
-- resource reference becomes the impose path instead of a printer uid:
-- imposing happens per material width, so the pattern points at
-- dk.sheet.impose.320, not at one of the three printers of that width.
-- copy_index becomes instance in the same pass (the not-null constraint was
-- already named after it).
--
-- Mapping: the printer of the old resource_uid gives the path, its first,
-- second and fourth level give the impose path
-- (site.material.print.width.* -> site.material.impose.width).
-- Measured before writing this: all 455 rows resolve to a printer, and no
-- two rows collide on (impose path, weekday, step, material_id).
--
-- Run sql/mock/{material_impose_plan,crud_material_impose_plan,generate_plan,
-- get_print_schedule_materials}.sql right after this — those three functions
-- read the table and break until they are recreated.

BEGIN;

-- 1. the table and its columns
ALTER TABLE mock.material_resource_plan RENAME TO material_impose_plan;
ALTER TABLE mock.material_impose_plan RENAME COLUMN material_resource_plan_id TO material_impose_plan_id;
ALTER TABLE mock.material_impose_plan RENAME COLUMN copy_index TO instance;

-- 2. the impose path, filled from the printer the row used to point at.
--    No foreign key: uq_resource_path is a partial index, which cannot back
--    one — relation.resource stays the owner of the tree.
ALTER TABLE mock.material_impose_plan ADD COLUMN resource_path ltree;

UPDATE mock.material_impose_plan m
SET resource_path = (subpath(r.resource_path, 0, 1)::text || '.' ||
                     subpath(r.resource_path, 1, 1)::text || '.impose.' ||
                     subpath(r.resource_path, 3, 1)::text)::ltree
FROM relation.resource r
WHERE r.resource_uid = m.resource_uid
  AND nlevel(r.resource_path) >= 4;

DO $$
DECLARE
    v_unmapped integer;
BEGIN
    SELECT count(*) INTO v_unmapped
    FROM mock.material_impose_plan
    WHERE resource_uid IS NOT NULL AND resource_path IS NULL;

    IF v_unmapped > 0 THEN
        RAISE EXCEPTION '% plan rows have a resource_uid that resolves to no printer path', v_unmapped;
    END IF;
END $$;

ALTER TABLE mock.material_impose_plan DROP COLUMN resource_uid;

-- 3. names that still carry the old table
ALTER INDEX mock.ix_material_resource_plan_lane RENAME TO ix_material_impose_plan;
ALTER TABLE mock.material_impose_plan RENAME CONSTRAINT material_resource_plan_pkey TO material_impose_plan_pkey;
ALTER TABLE mock.material_impose_plan RENAME CONSTRAINT material_resource_plan_weekday_check TO material_impose_plan_weekday_check;
ALTER TABLE mock.material_impose_plan RENAME CONSTRAINT material_resource_plan_sort_order_check TO material_impose_plan_sort_order_check;
ALTER TABLE mock.material_impose_plan RENAME CONSTRAINT material_resource_plan_instance_id_not_null TO material_impose_plan_instance_not_null;

-- the index was named after the lane it serves, but sits on the plan table
-- and now indexes the path instead of the uid
DROP INDEX mock.ix_material_impose_plan;
CREATE INDEX ix_material_impose_plan
    ON mock.material_impose_plan (weekday, step, resource_path, sort_order, moved_at DESC);

-- 4. mock.material_resource_plan_lane keeps its name on purpose: it is
--    redundant (action.lane_item.source_ref already carries plan_id:date) and
--    disappears when get_print_schedule_materials moves to lane items.

COMMIT;

-- expected: 455 rows over 4 impose paths —
-- dk.sheet.impose.320 (266), dk.sheet.impose.210 (84),
-- bh.sheet.impose.320 (70), bh.sheet.impose.210 (35)
