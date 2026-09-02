# planned — ontworpen, nog niet uitgerold

Deze bestanden beschrijven het **volgende** impositiemodel: lidmaatschap van
imposities in lane items als append-only reeks (`moved_at`), met verwijzingen
naar `production.imposition` in plaats van `legacy.nest`. Geen van deze
objecten staat in de database.

Wat er nu wél live is: `action.imposition_lane_item` als **platte** linktabel
(`imposition_id`, `lane_item_id`, `sort_order`), waarbij `imposition_id`
voorlopig een alias van `legacy.nest.nest_id` is. Zie
`sql/action/imposition_lane_item.sql`.

De stap hiernaartoe is de verhuizing van `legacy.nest` naar
`production.imposition`.
