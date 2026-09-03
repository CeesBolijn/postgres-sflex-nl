-- action.nest_lane_item becomes action.imposition_lane_item, nest_id becomes
-- imposition_id. Nothing else changes: the table stays the flat link it is,
-- and imposition_id is for now an alias of legacy.nest.nest_id — the same
-- trick as imposition_group_id being an alias of material_id. Moving
-- legacy.nest to production.imposition is the next step; the richer
-- append-only design for that lives in sql/action/planned/.
--
-- Run these right after, they read the table:
--   sql/legacy/crud_nest.sql
--   sql/action/crud_object.sql
--   sql/mock/get_impose_plan.sql
--   sql/mock/get_production_plan.sql

BEGIN;

ALTER TABLE action.nest_lane_item RENAME TO imposition_lane_item;
ALTER TABLE action.imposition_lane_item RENAME COLUMN nest_id TO imposition_id;

ALTER TABLE action.imposition_lane_item
    RENAME CONSTRAINT nest_lane_item_pk TO imposition_lane_item_pk;

ALTER INDEX action.ix_nest_lane_item_lane_item_id
    RENAME TO ix_imposition_lane_item_lane_item_id;

COMMENT ON COLUMN action.imposition_lane_item.imposition_id IS
    'The imposition that was made. Alias of legacy.nest.nest_id until nests move to production.imposition.';

COMMIT;

-- expected: 13477 rows, unchanged
