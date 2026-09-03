-- ============================================================
-- Fix: legacy.resource_data_log was dropped, its successor is log.data —
-- but three readers still queried the old table and errored on every call
-- (this is why the nest detail came up empty):
--     legacy.get_nest_detail     (nest_detail, 51)
--     legacy.get_nest_list       (intermediate_stock, nest_filter)
--     legacy.get_resource_queue  (resource_queue)
--
-- log.data had no index on nest_name; the nest lookups get one here.
--
-- >>> then run (all three drop themselves):
--     sql/legacy/get_nest_detail.sql
--     sql/legacy/get_nest_list.sql
--     sql/legacy/get_resource_queue.sql
-- ============================================================

create index ix_data_nest_time
    on log.data (nest_name, start_at)
    where nest_name is not null;
