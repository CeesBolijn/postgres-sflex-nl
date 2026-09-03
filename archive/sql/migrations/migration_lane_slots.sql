-- ============================================================
-- Migration: nest planning phases 1 + 2
-- (docs/nest-planning-lane-items.md)
--
-- Phase 1: clean up — lanes without lane_date are invalid (701
-- orphans, nothing hangs on them), production_orderline_lane_item
-- is dead (0 rows, wrong idea).
-- Phase 2: slots for the future — action.imposition_group_lane_item, the
-- slot stamping in mock.generate_plan, and a backfill onto the
-- plans that already exist.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1. clean up
-- ------------------------------------------------------------
DELETE FROM action.lane WHERE lane_date IS NULL;   -- plan_lane cascades

ALTER TABLE action.lane ALTER COLUMN lane_date SET NOT NULL;

DROP TABLE action.production_orderline_lane_item;

-- ------------------------------------------------------------
-- 2. the imposition group link per slot (group ids seeded 1:1 from
--    material ids by sql/migration_imposition_group.sql — run that first)
-- ------------------------------------------------------------
CREATE TABLE action.imposition_group_lane_item
(
    imposition_group_id integer NOT NULL
        REFERENCES catalog.imposition_group,
    lane_item_id bigint NOT NULL
        REFERENCES action.lane_item
            ON DELETE CASCADE,
    CONSTRAINT imposition_group_lane_item_pk
        PRIMARY KEY (imposition_group_id, lane_item_id)
);

ALTER TABLE action.imposition_group_lane_item OWNER TO xfw3;

CREATE INDEX ix_imposition_group_lane_item_lane_item_id
    ON action.imposition_group_lane_item (lane_item_id);

-- >>> now run sql/mock/generate_plan.sql (create or replace):
--     new plans get their slots + group links stamped from the pattern

-- ------------------------------------------------------------
-- 3. backfill: stamp slots onto the already-created plans of
--    today and later (idempotent via the source/source_ref key)
-- ------------------------------------------------------------
WITH slot AS (
    INSERT INTO action.lane_item
        (lane_id, sort_order, start_offset_in_seconds, is_pinned,
         no_split, level, source, source_ref)
    SELECT l.lane_id, m.sort_order, m.start_offset_in_seconds,
           coalesce(m.is_pinned, false), true, 0,
           'material-plan', m.material_resource_plan_id || ':' || p.plan_date
    FROM action.plan p
    JOIN action.plan_lane pl ON pl.plan_id = p.plan_id
    JOIN action.lane l ON l.lane_id = pl.lane_id
    JOIN mock.material_resource_plan_lane mrpl ON mrpl.lane_id = l.lane_id
    JOIN mock.material_resource_plan m ON m.material_resource_plan_id = mrpl.material_resource_plan_id
    WHERE p.type = 'material-resource-plan'
      AND p.plan_date >= current_date
    ON CONFLICT (source, source_ref) DO NOTHING
    RETURNING lane_item_id, lane_id
)
INSERT INTO action.imposition_group_lane_item (imposition_group_id, lane_item_id)
SELECT m.material_id, s.lane_item_id
FROM slot s
JOIN mock.material_resource_plan_lane mrpl ON mrpl.lane_id = s.lane_id
JOIN mock.material_resource_plan m ON m.material_resource_plan_id = mrpl.material_resource_plan_id
WHERE m.material_id IS NOT NULL
ON CONFLICT DO NOTHING;

COMMIT;
