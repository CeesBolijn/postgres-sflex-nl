-- ============================================================
-- Migration: the OEE read moves to the flat lookup — nothing else.
--
-- log.lookup is new and holds the simplified lookup_resource_state
-- (flat, counts_as, alias_of, no block/color/hierarchy; mirror in
-- json/lookup/log/lookup_resource_state.json). relation.lookup keeps
-- the old nested form, so every other reader (get_resource_state,
-- _aggregate, _current, _produced, plan_batch/impact, plan_timeline,
-- the mocks — the whole v1 page included) keeps running unchanged.
-- They move over later, one by one.
--
-- log.get_resource_state_shift_totals is rebuilt on the new lookup:
--   - bucket totals (counts_as) per group in param_json:
--     total_shift_hours, producing_hours, breakdown_hours,
--     offline_hours, planned_hours
--   - the formulas in a jsonb variable (v_formula_json):
--       production_hours     = total_shift_hours - (breakdown_hours + offline_hours)
--       producing_oee        = producing_hours / production_hours * 100
--       breakdown_percentage = breakdown_hours / total_shift_hours * 100
--       offline_percentage   = offline_hours  / total_shift_hours * 100
--       planned_percentage   = planned_hours  / total_shift_hours * 100
--   - public.evaluate_many_nas computes them; the result is oee_json
--   - v_excluded_states is gone; total_shift_hours = window length
--     times the resources in the group, never a sum of logged states
--   - the starved.operator/blocked.operator CASE is replaced by
--     alias_of from the lookup
--
-- Return shape changed (hence the DROP): total_duration_seconds,
-- duration_percent and parent_percent are gone; duration_percentage,
-- param_json and oee_json are new. data_group 62 follows in a
-- separate step.
--
-- Run order:
--   1. this block
--   2. sql/update_log_lookup_resource_state.sql  (the lookup content)
--   3. sql/log/get_resource_state_shift_totals.sql
--   4. the verification at the bottom
-- ============================================================

BEGIN;

-- same shape as relation.lookup; see sql/log/lookup.sql
CREATE TABLE log.lookup
(
    lookup text NOT NULL
        CONSTRAINT pk_log_lookup
            PRIMARY KEY,
    lookup_json jsonb
);

ALTER TABLE log.lookup OWNER TO xfw3;

DROP FUNCTION log.get_resource_state_shift_totals(p_resource_uids text[], p_until timestamp with time zone, p_days integer, p_line_type text, p_states text[], p_include_weekends boolean, p_include_mandatory_days_off boolean, p_include_shifts boolean, p_group_by text, p_tenant_ids integer[]);

-- >>> now run:
--     sql/update_log_lookup_resource_state.sql
--     sql/log/get_resource_state_shift_totals.sql

COMMIT;


-- ============================================================
-- verification
-- ============================================================

-- 1. the OEE read for one day, printers grouped per resource:
--    param_json carries the bucket hours, oee_json the evaluated
--    formulas
SELECT shift_date, shift_index, resource_name, state,
       round(duration_seconds / 3600.0, 2)   AS hours,
       duration_percentage,
       param_json,
       oee_json ->> 'producing_oee'          AS producing_oee,
       oee_json ->> 'breakdown_percentage'   AS breakdown_percentage,
       oee_json ->> 'offline_percentage'     AS offline_percentage,
       oee_json ->> 'production_hours'       AS production_hours
FROM log.get_resource_state_shift_totals(
         NULL, now(), 1, NULL, NULL, true, true, true, 'resource', NULL)
WHERE step = 'print'
ORDER BY resource_name, shift_index, sort_order
LIMIT 40;

-- 2. the formula check by hand; expected: recomputed equals evaluated
SELECT DISTINCT shift_date, shift_index, resource_name,
       (param_json ->> 'total_shift_hours')::numeric                       AS total_shift_hours,
       (param_json ->> 'producing_hours')::numeric                         AS producing_hours,
       round((param_json ->> 'producing_hours')::numeric
             / nullif((param_json ->> 'total_shift_hours')::numeric
                      - (param_json ->> 'breakdown_hours')::numeric
                      - (param_json ->> 'offline_hours')::numeric, 0) * 100, 2) AS producing_oee_recomputed,
       round((oee_json ->> 'producing_oee')::numeric, 2)                   AS producing_oee_evaluated
FROM log.get_resource_state_shift_totals(
         NULL, now(), 1, NULL, NULL, true, true, true, 'resource', NULL)
WHERE step = 'print'
ORDER BY resource_name, shift_index
LIMIT 20;

-- 3. no state resolves to null (starved.operator included);
--    expected: no rows
SELECT DISTINCT state
FROM log.get_resource_state_shift_totals(
         NULL, now(), 7, NULL, NULL, true, true, true, 'resource', NULL)
WHERE state_json IS NULL;

-- 4. the old readers still run on the untouched relation.lookup;
--    expected: rows, none with a null state
SELECT count(*)                                   AS rows,
       count(*) FILTER (WHERE g.state IS NULL)    AS null_states
FROM log.get_resource_state_aggregate(NULL, NULL, now(), NULL) g;
