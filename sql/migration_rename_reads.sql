-- The reads get their final names: get_nest_schedule becomes
-- get_impose_plan (nesting is imposing, and what it returns is a plan),
-- get_print_schedule_materials becomes get_plan_lanes (one generic read for
-- the lanes of any plan), get_production_schedule becomes get_production_plan.
-- mock.get_print_schedule keeps its name — it is a template, and schedule is
-- the word for a template.
--
-- Run sql/mock/{get_impose_plan,get_plan_lanes,get_production_plan}.sql first
-- (they drop the old function names themselves), then this, then the data_group
-- update that points the srcs at the new data_tables.

BEGIN;

-- both the original name and the get_imposition_plan step in between, so the
-- script lands whatever state the row is in
UPDATE site.data_table
SET data_table  = 'get_impose_plan',
    query       = 'mock.get_impose_plan',
    description = 'get_impose_plan'
WHERE data_table IN ('get_nest_schedule', 'get_imposition_plan');

UPDATE site.data_table
SET data_table  = 'get_plan_lanes',
    query       = 'mock.get_plan_lanes',
    description = 'get_plan_lanes'
WHERE data_table IN ('get_print_schedule_materials', 'get_plan_lanes');

UPDATE site.data_table
SET data_table  = 'get_production_plan',
    query       = 'mock.get_production_plan',
    description = 'get_production_plan'
WHERE data_table IN ('get_production_schedule', 'get_production_plan');

COMMIT;
