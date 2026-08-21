-- ============================================================
-- Migration: rename mutation/event log tables from *_log to *_event
--
-- Scope (6 tables):
--   job.cart_log            -> job.cart_event
--   job.spec_log            -> job.spec_event
--   log.spec_log            -> log.spec_event
--   mock.spec_log           -> mock.spec_event
--   production.imposition_log -> production.imposition_event
--   action.lane_item_log    -> action.lane_item_event
--
-- Explicitly NOT renamed: mapping.status_log (stays as-is), everything
-- in the legacy schema (legacy.nest_log, legacy.log, legacy.specs_log,
-- ...), the tables behind log.crud_state_log / crud_data_log /
-- crud_error_log / crud_hr_data_log / crud_hr_shift_planning_log,
-- and job.crud_specs_log.
--
-- All names below were taken from the live catalogs (PostgreSQL 18.2).
-- Renames do not cascade in Postgres: columns, constraints, indexes
-- and sequences are all renamed explicitly. Named NOT NULL constraints
-- (PG18) are included. Run in one transaction.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1. job.cart_log -> job.cart_event
-- ------------------------------------------------------------
ALTER TABLE job.cart_log RENAME TO cart_event;
ALTER TABLE job.cart_event RENAME COLUMN cart_log_id TO cart_event_id;
ALTER TABLE job.cart_event RENAME CONSTRAINT cart_log_pkey TO cart_event_pkey;
ALTER TABLE job.cart_event RENAME CONSTRAINT cart_log_cart_id_fkey TO cart_event_cart_id_fkey;
ALTER TABLE job.cart_event RENAME CONSTRAINT cart_log_after_status_check TO cart_event_after_status_check;
ALTER TABLE job.cart_event RENAME CONSTRAINT cart_log_cart_id_not_null TO cart_event_cart_id_not_null;
ALTER TABLE job.cart_event RENAME CONSTRAINT cart_log_cart_log_id_not_null TO cart_event_cart_event_id_not_null;
ALTER TABLE job.cart_event RENAME CONSTRAINT cart_log_moved_at_not_null TO cart_event_moved_at_not_null;
ALTER TABLE job.cart_event RENAME CONSTRAINT cart_log_status_not_null TO cart_event_status_not_null;
ALTER INDEX job.cart_log_cart_id_moved_at_idx RENAME TO cart_event_cart_id_moved_at_idx;
ALTER SEQUENCE job.cart_log_cart_log_id_seq RENAME TO cart_event_cart_event_id_seq;

-- ------------------------------------------------------------
-- 2. job.spec_log -> job.spec_event
-- ------------------------------------------------------------
ALTER TABLE job.spec_log RENAME TO spec_event;
ALTER TABLE job.spec_event RENAME COLUMN spec_log_id TO spec_event_id;
ALTER TABLE job.spec_event RENAME CONSTRAINT spec_log_pkey TO spec_event_pkey;
ALTER TABLE job.spec_event RENAME CONSTRAINT spec_log_spec_id_fkey TO spec_event_spec_id_fkey;
ALTER TABLE job.spec_event RENAME CONSTRAINT spec_log_move_valid TO spec_event_move_valid;
ALTER TABLE job.spec_event RENAME CONSTRAINT spec_log_no_self TO spec_event_no_self;
ALTER TABLE job.spec_event RENAME CONSTRAINT spec_log_qty_positive TO spec_event_qty_positive;
ALTER TABLE job.spec_event RENAME CONSTRAINT spec_log_moved_at_not_null TO spec_event_moved_at_not_null;
ALTER TABLE job.spec_event RENAME CONSTRAINT spec_log_qty_not_null TO spec_event_qty_not_null;
ALTER TABLE job.spec_event RENAME CONSTRAINT spec_log_remaining_impact_delta_not_null TO spec_event_remaining_impact_delta_not_null;
ALTER TABLE job.spec_event RENAME CONSTRAINT spec_log_resource_uids_not_null TO spec_event_resource_uids_not_null;
ALTER TABLE job.spec_event RENAME CONSTRAINT spec_log_spec_id_not_null TO spec_event_spec_id_not_null;
ALTER TABLE job.spec_event RENAME CONSTRAINT spec_log_spec_log_id_not_null TO spec_event_spec_event_id_not_null;
ALTER INDEX job.spec_log_spec_id_idx RENAME TO spec_event_spec_id_idx;
ALTER SEQUENCE job.spec_log_spec_log_id_seq RENAME TO spec_event_spec_event_id_seq;

-- ------------------------------------------------------------
-- 3. log.spec_log -> log.spec_event
-- ------------------------------------------------------------
ALTER TABLE log.spec_log RENAME TO spec_event;
ALTER TABLE log.spec_event RENAME COLUMN spec_log_id TO spec_event_id;
ALTER TABLE log.spec_event RENAME CONSTRAINT spec_log_pkey TO spec_event_pkey;
ALTER TABLE log.spec_event RENAME CONSTRAINT spec_log_spec_id_fkey TO spec_event_spec_id_fkey;
ALTER TABLE log.spec_event RENAME CONSTRAINT spec_log_move_valid TO spec_event_move_valid;
ALTER TABLE log.spec_event RENAME CONSTRAINT spec_log_no_self TO spec_event_no_self;
ALTER TABLE log.spec_event RENAME CONSTRAINT spec_log_moved_at_not_null TO spec_event_moved_at_not_null;
ALTER TABLE log.spec_event RENAME CONSTRAINT spec_log_qty_not_null TO spec_event_qty_not_null;
ALTER TABLE log.spec_event RENAME CONSTRAINT spec_log_resource_uids_not_null TO spec_event_resource_uids_not_null;
ALTER TABLE log.spec_event RENAME CONSTRAINT spec_log_spec_id_not_null TO spec_event_spec_id_not_null;
ALTER TABLE log.spec_event RENAME CONSTRAINT spec_log_spec_log_id_not_null TO spec_event_spec_event_id_not_null;
ALTER INDEX log.spec_log_spec_id_idx RENAME TO spec_event_spec_id_idx;
ALTER SEQUENCE log.spec_log_spec_log_id_seq RENAME TO spec_event_spec_event_id_seq;

-- ------------------------------------------------------------
-- 4. mock.spec_log -> mock.spec_event
-- ------------------------------------------------------------
ALTER TABLE mock.spec_log RENAME TO spec_event;
ALTER TABLE mock.spec_event RENAME COLUMN spec_log_id TO spec_event_id;
ALTER TABLE mock.spec_event RENAME CONSTRAINT spec_log_pkey TO spec_event_pkey;
ALTER TABLE mock.spec_event RENAME CONSTRAINT spec_log_spec_id_fkey TO spec_event_spec_id_fkey;
ALTER TABLE mock.spec_event RENAME CONSTRAINT spec_log_move_valid TO spec_event_move_valid;
ALTER TABLE mock.spec_event RENAME CONSTRAINT spec_log_no_self TO spec_event_no_self;
ALTER TABLE mock.spec_event RENAME CONSTRAINT spec_log_amount_not_null TO spec_event_amount_not_null;
ALTER TABLE mock.spec_event RENAME CONSTRAINT spec_log_moved_at_not_null TO spec_event_moved_at_not_null;
ALTER TABLE mock.spec_event RENAME CONSTRAINT spec_log_resource_uids_not_null TO spec_event_resource_uids_not_null;
ALTER TABLE mock.spec_event RENAME CONSTRAINT spec_log_spec_id_not_null TO spec_event_spec_id_not_null;
ALTER TABLE mock.spec_event RENAME CONSTRAINT spec_log_spec_log_id_not_null TO spec_event_spec_event_id_not_null;
ALTER INDEX mock.spec_log_spec_id_idx RENAME TO spec_event_spec_id_idx;
ALTER SEQUENCE mock.spec_log_spec_log_id_seq RENAME TO spec_event_spec_event_id_seq;

-- ------------------------------------------------------------
-- 5. production.imposition_log -> production.imposition_event
--    (also cleans up the old "nest_log" leftovers)
-- ------------------------------------------------------------
ALTER TABLE production.imposition_log RENAME TO imposition_event;
ALTER TABLE production.imposition_event RENAME COLUMN imposition_log_id TO imposition_event_id;
ALTER TABLE production.imposition_event RENAME CONSTRAINT imposition_log_pkey TO imposition_event_pkey;
ALTER TABLE production.imposition_event RENAME CONSTRAINT imposition_log_nest_id_fkey TO imposition_event_imposition_id_fkey;
ALTER TABLE production.imposition_event RENAME CONSTRAINT imposition_log_move_valid TO imposition_event_move_valid;
ALTER TABLE production.imposition_event RENAME CONSTRAINT imposition_log_no_self TO imposition_event_no_self;
ALTER TABLE production.imposition_event RENAME CONSTRAINT nest_log_moved_at_not_null TO imposition_event_moved_at_not_null;
ALTER TABLE production.imposition_event RENAME CONSTRAINT nest_log_nest_id_not_null TO imposition_event_imposition_id_not_null;
ALTER TABLE production.imposition_event RENAME CONSTRAINT nest_log_nest_log_id_not_null TO imposition_event_imposition_event_id_not_null;
ALTER TABLE production.imposition_event RENAME CONSTRAINT nest_log_qty_not_null TO imposition_event_qty_not_null;
ALTER TABLE production.imposition_event RENAME CONSTRAINT nest_log_remaining_impact_delta_not_null TO imposition_event_remaining_impact_delta_not_null;
ALTER TABLE production.imposition_event RENAME CONSTRAINT nest_log_resource_uids_not_null TO imposition_event_resource_uids_not_null;
ALTER INDEX production.imposition_log_imposition_id_idx RENAME TO imposition_event_imposition_id_idx;
ALTER SEQUENCE production.nest_log_nest_log_id_seq RENAME TO imposition_event_imposition_event_id_seq;

-- ------------------------------------------------------------
-- 6. action.lane_item_log -> action.lane_item_event
-- ------------------------------------------------------------
ALTER TABLE action.lane_item_log RENAME TO lane_item_event;
ALTER TABLE action.lane_item_event RENAME COLUMN lane_item_log_id TO lane_item_event_id;
ALTER TABLE action.lane_item_event RENAME CONSTRAINT lane_item_log_pkey TO lane_item_event_pkey;
ALTER TABLE action.lane_item_event RENAME CONSTRAINT lane_item_log_lane_item_id_fkey TO lane_item_event_lane_item_id_fkey;
ALTER TABLE action.lane_item_event RENAME CONSTRAINT lane_item_log_lane_item_id_not_null TO lane_item_event_lane_item_id_not_null;
ALTER TABLE action.lane_item_event RENAME CONSTRAINT lane_item_log_lane_item_log_id_not_null TO lane_item_event_lane_item_event_id_not_null;
ALTER TABLE action.lane_item_event RENAME CONSTRAINT lane_item_log_moved_at_not_null TO lane_item_event_moved_at_not_null;
ALTER TABLE action.lane_item_event RENAME CONSTRAINT lane_item_log_status_not_null TO lane_item_event_status_not_null;
ALTER INDEX action.lane_item_log_lane_item_id_moved_at_idx RENAME TO lane_item_event_lane_item_id_moved_at_idx;
ALTER SEQUENCE action.lane_item_log_lane_item_log_id_seq RENAME TO lane_item_event_lane_item_event_id_seq;

-- ------------------------------------------------------------
-- 7. Functions. plpgsql bodies resolve table names at execution
--    time, so every function touching these tables breaks at
--    runtime until its file is re-applied. The files use
--    "create function" (not "create or replace"), so drop first.
--
--    Renamed function (old name + signature dropped here, new
--    name comes from the re-applied file):
-- ------------------------------------------------------------
DROP FUNCTION log.crud_spec_log(jsonb, boolean);

--    Same-name functions, dropped so their files re-apply cleanly:
DROP FUNCTION job.get_cart_statuses(bigint[], timestamp with time zone);
DROP FUNCTION job.spec_unit_status_update_batch(bigint, integer, integer, jsonb, text[]);
DROP FUNCTION mock.get_stock(integer, numeric);
DROP FUNCTION production.imposition_unit_status_update(bigint, integer, integer, text[]);

-- >>> Now re-run these files (in this order is fine):
--     sql/log/crud_spec_event.sql
--     sql/job/get_cart_statuses.sql
--     sql/job/spec_unit_status_update_batch.sql
--     sql/mock/get_stock.sql
--     sql/production/imposition_unit_status_update.sql

COMMIT;

-- ============================================================
-- Post-migration note (outside this script): application code
-- that calls crud_spec_log, or reads columns such as spec_log_id /
-- cart_log_id / imposition_log_id / lane_item_log_id, must move
-- to the new names in the same release.
-- ============================================================
