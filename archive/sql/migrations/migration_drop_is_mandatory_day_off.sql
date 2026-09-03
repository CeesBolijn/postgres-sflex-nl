-- Final step of migration_dates_tenants_day_off.sql: every reader has been
-- adapted to tenants_mandatory_day_off, so the boolean column can go.
-- The guard aborts when any user function still mentions the column, so a
-- forgotten reader surfaces here instead of at its next call.

BEGIN;

DO $$
DECLARE
    v_fn text;
BEGIN
    SELECT string_agg(n.nspname || '.' || p.proname, ', ')
    INTO v_fn
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
      AND p.prosrc ILIKE '%is_mandatory_day_off%';

    IF v_fn IS NOT NULL THEN
        RAISE EXCEPTION 'is_mandatory_day_off is still read by: %', v_fn;
    END IF;
END $$;

ALTER TABLE action.dates DROP COLUMN is_mandatory_day_off;

COMMIT;
