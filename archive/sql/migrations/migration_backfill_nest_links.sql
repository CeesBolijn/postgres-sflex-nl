-- ============================================================
-- Backfill: hang the existing legacy.nest rows of the last three
-- weeks (and ahead) on their planned lane items, with the same
-- resolution as legacy.crud_nest (docs/nest-planning-lane-items.md
-- §3). Idempotent: links are replaced as a set per nest, the
-- created lane items reuse their source/source_ref key.
-- Run AFTER sql/migration_lane_slots.sql.
-- ============================================================

BEGIN;

CREATE TEMP TABLE nest_link ON COMMIT DROP AS
WITH payload AS (
    SELECT n.nest_id, n.sort_order,
           (n.nest_json ->> 'material_id')::integer        AS material_id,
           (n.nest_json ->> 'production_line_id')::integer AS production_line_id,
           (n.nested_at AT TIME ZONE 'Europe/Amsterdam')::date AS plan_date,
           extract(epoch FROM (n.nested_at AT TIME ZONE 'Europe/Amsterdam')::time)::integer AS nest_seconds,
           lower(COALESCE(n.nest_json ->> 'status', '')) LIKE 'cancel%' AS is_cancelled
    FROM legacy.nest n
    WHERE n.nested_at >= current_date - 21
)
SELECT p.nest_id, p.sort_order, p.nest_seconds, p.is_cancelled,
       lane.lane_id, item.lane_item_id
FROM payload p
LEFT JOIN relation.production_line prl ON prl.line_id = p.production_line_id
LEFT JOIN LATERAL (
    SELECT ap.plan_id
    FROM action.plan ap
    WHERE ap.plan_date = p.plan_date
      AND ap.type = 'material-resource-plan'
      AND (prl.line_type IS NULL OR ap.line_type = prl.line_type)
    ORDER BY ap.plan_id DESC
    LIMIT 1
) tp ON true
LEFT JOIN LATERAL (
    -- the lane of the nest material on that plan, through the group
    -- link of its lane items. imposition_group_id acts as an alias of
    -- material_id for now (the groups were seeded 1:1 from the material
    -- ids); later the nests resolve their real imposition group here.
    SELECT l.lane_id
    FROM action.plan_lane apl
    JOIN action.lane l ON l.lane_id = apl.lane_id
    JOIN action.lane_item li2 ON li2.lane_id = l.lane_id
    JOIN action.imposition_group_lane_item igli ON igli.lane_item_id = li2.lane_item_id
    WHERE apl.plan_id = tp.plan_id
      AND igli.imposition_group_id = p.material_id
    LIMIT 1
) lane ON true
LEFT JOIN LATERAL (
    -- latest lane item starting at or before the nest moment, else the first of the day
    SELECT li.lane_item_id
    FROM action.lane_item li
    WHERE li.lane_id = lane.lane_id
      AND li.level = 0
    ORDER BY (COALESCE(li.start_offset_in_seconds, 0) <= p.nest_seconds) DESC,
             CASE WHEN COALESCE(li.start_offset_in_seconds, 0) <= p.nest_seconds
                  THEN -COALESCE(li.start_offset_in_seconds, 0)
                  ELSE COALESCE(li.start_offset_in_seconds, 0) END
    LIMIT 1
) item ON true;

INSERT INTO action.lane_item
    (lane_id, sort_order, start_offset_in_seconds, no_split, level, source, source_ref)
SELECT ns.lane_id, -1 * ns.nest_id, ns.nest_seconds, true, 0, 'nest', ns.nest_id::text
FROM nest_link ns
WHERE ns.lane_item_id IS NULL
  AND ns.lane_id IS NOT NULL
  AND NOT ns.is_cancelled
ON CONFLICT ON CONSTRAINT lane_item_source_ref_uq DO NOTHING;

DELETE FROM action.nest_lane_item nli
USING action.lane_item li
WHERE nli.lane_item_id = li.lane_item_id
  AND li.source IN ('material-plan', 'nest')
  AND nli.nest_id IN (SELECT ns.nest_id FROM nest_link ns);

INSERT INTO action.nest_lane_item (nest_id, lane_item_id, sort_order)
SELECT ns.nest_id,
       COALESCE(ns.lane_item_id, own.lane_item_id),
       ns.sort_order
FROM nest_link ns
LEFT JOIN action.lane_item own
       ON own.source = 'nest' AND own.source_ref = ns.nest_id::text
WHERE NOT ns.is_cancelled
  AND COALESCE(ns.lane_item_id, own.lane_item_id) IS NOT NULL
ON CONFLICT DO NOTHING;

-- how much got linked
SELECT count(*)                                          AS nests_in_window,
       count(*) FILTER (WHERE lane_item_id IS NOT NULL)  AS on_planned_lane_item,
       count(*) FILTER (WHERE lane_item_id IS NULL
                          AND lane_id IS NOT NULL)       AS on_created_lane_item,
       count(*) FILTER (WHERE lane_id IS NULL)           AS no_lane_found
FROM nest_link;

COMMIT;
