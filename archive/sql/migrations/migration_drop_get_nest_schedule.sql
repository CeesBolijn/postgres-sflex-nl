-- Drop action.get_nest_schedule. It was the older sibling of
-- mock.get_nest_schedule (now mock.get_impose_plan) and is referenced by no
-- data_table, no data_group, no other function and no view — only by its own
-- definition file, which moved to archive/sql/action/get_nest_schedule.sql.
-- Listed in docs/archive-analysis.md, appendix "nergens gerefereerd".
--
-- The name mock.get_nest_schedule is already gone: sql/mock/get_impose_plan.sql
-- drops both of its old signatures.

BEGIN;

DROP FUNCTION IF EXISTS action.get_nest_schedule(timestamp with time zone, text, numeric);

COMMIT;

-- Verify afterwards: expect zero rows.
-- SELECT n.nspname, p.proname
-- FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
-- WHERE p.proname LIKE 'get_nest_schedule%';
