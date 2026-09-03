-- ============================================================
-- Full manifest rebuild: the item codes changed, and
-- component_specs.manifest_json becomes an aggregate per scope
--   { "<scope>": { "i18n": {...}, "item_code_paths": [...] } }
--
-- >>> run FIRST (both drop themselves):
--     sql/mapping/update_component_specs_manifest.sql   (new)
--     sql/mapping/create_spec_unit_manifest.sql         (delegates the json)
-- ============================================================

COMMENT ON COLUMN mapping.component_specs.manifest_json IS
    'Aggregated manifest of this orderline, one object per scope: {"<scope>": {"i18n": {...}, "item_code_paths": [...]}}; written by mapping.create_spec_unit_manifest in the same pass as spec_unit_manifest, rebuilt retroactively by mapping.update_component_specs_manifest.';

-- Rebuild every orderline that has manifest rows today (85k), in batches of
-- 5000: each batch re-resolves the xbom rows (picking up the updated item
-- codes) AND rewrites manifest_json in the new shape. One transaction,
-- expect a few minutes; the NOTICEs show progress.
DO $$
DECLARE
    v_ids  integer[];
    v_last integer := 0;
    v_done integer := 0;
BEGIN
    LOOP
        SELECT array_agg(b.production_orderline_id ORDER BY b.production_orderline_id)
        INTO   v_ids
        FROM (
            SELECT DISTINCT s.production_orderline_id
            FROM mapping.spec_unit_manifest s
            WHERE s.production_orderline_id > v_last
            ORDER BY 1
            LIMIT 5000
        ) b;

        EXIT WHEN v_ids IS NULL;

        PERFORM mapping.create_spec_unit_manifest(v_ids);

        v_last := v_ids[cardinality(v_ids)];
        v_done := v_done + cardinality(v_ids);
        RAISE NOTICE 'manifest rebuilt: % orderlines (up to orderline %)', v_done, v_last;
    END LOOP;
END $$;

-- afterwards: shape check, expect only the new object form
-- select jsonb_typeof(manifest_json) as vorm, count(*)
-- from mapping.component_specs where manifest_json is not null group by 1;
