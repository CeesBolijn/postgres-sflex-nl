-- mock.material_resource_plan_lane mapped a lane to its pattern row. That link
-- now lives on the lane item itself: source_ref is
-- <material_impose_plan_id>:<date>, with a unique index on (source,
-- source_ref). get_plan_lanes reads it there, so the table has no readers left.
--
-- Run sql/mock/get_plan_lanes.sql first — that is the last function that used
-- the detour.

BEGIN;

DO $$
DECLARE
    v_reader text;
BEGIN
    SELECT string_agg(n.nspname || '.' || p.proname, ', ')
    INTO v_reader
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
      AND p.prosrc LIKE '%material\_resource\_plan\_lane%';

    IF v_reader IS NOT NULL THEN
        RAISE EXCEPTION 'still read by: %', v_reader;
    END IF;
END $$;

DROP TABLE mock.material_resource_plan_lane;

COMMIT;
