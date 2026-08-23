-- ============================================================
-- Migration: the manifest travels on the spec row.
-- mapping.component_specs gains manifest_json, backfilled from
-- mapping.spec_unit_manifest; create_spec_unit_manifest keeps it
-- in step from now on. The dead resources_json / resource_uids
-- columns go (writer commented out long ago, no readers — the
-- resource_uids in legacy.get_nest_planning comes from its own
-- log CTE, not from component_specs).
--
-- mapping.spec_unit_manifest itself STAYS until
-- get_component_specs_with_manifest and get_unit_manifest_aggregate
-- read manifest_json instead.
-- ============================================================

BEGIN;

ALTER TABLE mapping.component_specs ADD COLUMN manifest_json jsonb;

COMMENT ON COLUMN mapping.component_specs.manifest_json IS
    'The evaluated manifest of this orderline (option_code, item_code, scope, param_json, config_json per xbom row); written by mapping.create_spec_unit_manifest in the same pass as spec_unit_manifest.';

DROP INDEX mapping.ix_component_specs_resource_uids;

ALTER TABLE mapping.component_specs
    DROP COLUMN resources_json,
    DROP COLUMN resource_uids;

-- backfill from the existing manifest rows
UPDATE mapping.component_specs cs
SET manifest_json = m.manifest_json
FROM (
    SELECT s.production_orderline_id,
           jsonb_agg(jsonb_build_object(
               'option_code', s.option_code,
               'item_code',   s.item_code,
               'scope',       s.scope,
               'param_json',  s.param_json,
               'config_json', s.config_json)
             ORDER BY s.sort_order) AS manifest_json
    FROM mapping.spec_unit_manifest s
    GROUP BY s.production_orderline_id
) m
WHERE cs.production_orderline_id = m.production_orderline_id;

COMMIT;

-- >>> then run (both drop themselves):
--     sql/mapping/create_spec_unit_manifest.sql
--     sql/mapping/get_production_orderline_detail.sql   (output gains manifest_json)
