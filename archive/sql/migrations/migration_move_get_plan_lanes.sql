-- get_plan_lanes moves from mock to action: the lane model lives in action,
-- and the read is the label source of every plan board (75, 76, 78, 81).
--
-- Run sql/action/get_plan_lanes.sql and sql/mock/get_impose_plan.sql first,
-- in one session: the first drops mock.get_plan_lanes and creates the action
-- version, the second re-points the only database caller.
--
-- The primary keys also change: copy_index is gone (a copy is a new lane
-- item, contract drag-and-drop), the lane item is the identity of a material
-- row, the resource of a resource-mode row.

BEGIN;

UPDATE site.data_table
SET query       = 'action.get_plan_lanes',
    description = 'get_plan_lanes',
    data_table_json = jsonb_set(
        data_table_json, '{primary_keys}',
        '["tenant_id", "material_id", "production_line_id", "lane_item_id", "resource_uid"]'::jsonb)
WHERE data_table = 'get_plan_lanes';

UPDATE site.data_table
SET data_table_json = jsonb_set(
        data_table_json, '{primary_keys}',
        '["tenant_id", "material_id", "production_line_id", "lane_item_id"]'::jsonb)
WHERE data_table = 'get_impose_plan';

-- verify: both rows, no copy_index left anywhere
SELECT data_table, query, data_table_json -> 'primary_keys' AS primary_keys
FROM site.data_table
WHERE data_table IN ('get_plan_lanes', 'get_impose_plan');

COMMIT;
