-- The chaining offset belongs to the resource, not to the pattern: every row
-- of mock.material_impose_plan carries 900, which is exactly the
-- next_start_lag_in_seconds of the impose resources. So the column goes, and
-- the reads take the value from relation.resource.resource_json.
--
-- Impose paths are left exactly as they are. An impose resource sits at the
-- width by default (dk.sheet.impose.320), but goes deeper when one machine
-- imposes on its own (dk.sheet.impose.320.uv.swissq.kudu) — the pattern
-- points at whichever level applies.
--
-- Run sql/mock/{crud_material_impose_plan,get_print_schedule_materials}.sql
-- right after this.

BEGIN;

-- every path the pattern points at must exist as a resource; the reads join
-- on it, so a dangling path silently costs the row its resource and name
DO $$
DECLARE
    v_dangling text;
BEGIN
    SELECT string_agg(DISTINCT p.resource_path::text, ', ')
    INTO v_dangling
    FROM mock.material_impose_plan p
    WHERE p.resource_path IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM relation.resource r
                      WHERE r.resource_path = p.resource_path);

    IF v_dangling IS NOT NULL THEN
        RAISE EXCEPTION 'plan rows point at impose paths without a resource: %', v_dangling;
    END IF;
END $$;

ALTER TABLE mock.material_impose_plan DROP COLUMN next_start_offset_in_seconds;

COMMIT;

-- expected: 455 rows over 5 impose paths, all resolving to a resource —
-- dk.sheet.impose.320 (175), dk.sheet.impose.320.uv.swissq.kudu (91),
-- dk.sheet.impose.210 (84), bh.sheet.impose.320 (70),
-- bh.sheet.impose.210 (35)
