-- ============================================================
-- Cleanup: the manifest now travels on component_specs.manifest_json,
-- so the aggregate reader and its last caller (an unused test board
-- function, no data group behind it) go. Repo files are already removed.
-- ============================================================

drop function if exists action.get_nest_schedule_test(timestamp with time zone, text, integer, integer, numeric, integer[]);
drop function if exists mapping.get_unit_manifest_aggregate(integer[], text);
