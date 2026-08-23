# Inventory: chats to harvest

Gesorteerd nieuw naar oud. Vink af zodra de functie/json in de repo staat en de chat verwijderd is.

| datum | onderwerp | wat eruit moet | status |
|---|---|---|---|
| 2026-08-10 16:54 | cutoff_times + locations opzet | ontwerp-discussie, nog geen definitieve sql | [ ] |
| 2026-08-10 16:48 | print/nest board optimalisatie | `mock.get_print_schedule_materials_test`, `mock.update_material_resource_plan_sort_order`, `mock.crud_material_resource_plan`, `mock.get_nest_schedule` | ⏳ chat nog actief vandaag — pas oogsten als afgerond |
| 2026-08-10 15:12 | lane items / nest items filtering | ontwerp-notitie (rubber duck), geen definitieve sql | [ ] |
| 2026-08-10 14:43 | schema's samenvoegen tot ERD | `database-erd.md` (mermaid) | ⚠️ concept staat in repo (`docs/database-erd.md`) — alleen de nu geoogste tabellen, nog aan te vullen |
| 2026-08-10 09:34 | multi-material configurators | concept, geen sql/json | [ ] |
| 2026-08-09 10:29 | equipment/resource printer settings | `relation.get_resource_printer_settings` | ✅ in repo (`sql/relation/get_resource_printer_settings.sql`) |
| 2026-08-09 07:04 | print schedule + timeline data_group | `mock.get_print_schedule`, `mock.get_print_schedule_materials`, timeline JSON config | [ ] |
| 2026-08-08 14:56 | shift employees refactor | `log.get_resource_shift_employees` | ⚠️ gedeeltelijk in repo — functie-body afgekapt in bron, zie TODO in bestand |
| 2026-08-08 11:09 | orderline detail debug | geen resultaat, niets te oogsten | [ ] |
| 2026-08-08 09:42 | production_order_amount | `mapping.crud_component_specs_orderline` (+ update statement) | [ ] |
| 2026-08-08 07:58 | multi-step production planning | `action.lane`, `lane_item`, `lane_item_dependency`, `order_lane_item`, `nest_lane_item`, `lane_item_event`, `mock.material_resource_plan_lane` | ⚠️ grotendeels in repo (`sql/action/lane_item.sql`) — `action.lane` zelf en `mock.material_resource_plan_lane` nog niet gevonden |
| 2026-08-07 07:57 | overlapping break times | geen structurele sql/json, eenmalige check | [ ] |
| 2026-08-07 06:12 | tenant hierarchy + rule_path | `relation.tenant`, `tenant_domain`, `action.rule_path_matches`, `action.rule_path_ancestors` | ⚠️ gedeeltelijk — de twee functies staan in `sql/action/rule_path.sql`, `relation.tenant`/`tenant_domain` DDL nog niet gevonden |
| 2026-08-06 10:49 | team/contact tabellen | `relation.team`, `relation.team_contact` | ⚠️ `relation.team` + `action.week_team` in repo (`sql/relation/team.sql`) — `team_contact` staat als voorstel in commentaar, nog niet bevestigd |
| 2026-08-06 07:31 | cutoff_time lookup | `action.cutoff_time` + index + lookup query | ⚠️ tabel + index in repo (`sql/action/cutoff_time.sql`) — losse lookup-query/functie nog niet gevonden |
| 2026-08-06 06:42 | printschema query | losse query, mogelijk vervangen door latere versie (check 08-09) | [ ] |
| 2026-08-05 16:32 | schaalbaarheid discussie | geen sql/json, wel argumentatie voor document | [ ] |
| 2026-08-04 15:37 | production_line i18n lookup | `relation.lookup` structuur voor productielijnen/hallen | [ ] |

## aangevuld: 29 juli t/m 4 augustus
| datum | onderwerp | wat eruit moet | status |
|---|---|---|---|
| 2026-08-02 09:31 | nest-planning, get_nest_schedule (grote sessie) | `action.get_nest_schedule_test`, `action.get_nest_moments`, `mapping.calculate_nest_date`, `production.get_timeline_view_segments`, `data_group_nest_schedule.json`, `component_specs_aggregate.sql` | ⚠️ let op — grotendeels vervangen door de versie in de chat van 10-11 aug (zie hierboven), check eerst welke nog geldig is voor je oogst |
| 2026-08-01 09:56 | timeline view segments + performance fix | `production.get_timeline_view_segments`, index-fix voor `log.crud_data_log`, `legacy.get_print_duration_according_to_specs` | ⚠️ mogelijk vervangen door latere versie, check tegen 08-02 en 08-09 |
| 2026-07-31 14:25 | mysql sync pipeline naar mapping | `mapping.crud_product`, `mapping.product` tabel | [ ] |
| 2026-07-31 09:12 | OEE `lookup_resource_state` json-ontwerp | json-structuur (nog geen sql) | [ ] |
| 2026-07-31 07:43 | resource allocation ledger | `core.line_item_resource`, `catalog.crud_line_item_resource`, `relation.resource` DDL, `line_item_resource.md` | [ ] |
| 2026-07-31 06:07 | get_nest_planning uitbreiden | `legacy.get_nest_planning` (met production_line_id, resource_uid/name, material_id) | [ ] |
| 2026-07-30 17:02 | library options normaliseren + xbom pipeline | `mapping.crud_spec_unit_manifest`, ~~`mapping.get_unit_manifest_aggregate`~~ (vervallen — manifest_json staat op component_specs), ~~`mapping.get_component_specs_with_manifest`~~ (vervangen door `mapping.get_production_orderline_manifest`), `mapping.crud_sales_orderline_option` | [ ] |
| 2026-07-29 09:46 | nest time scale, uurlijkse intervallen | `get_timeline_view_segments` (vroege versie) + `lookup_timeline_views` json | ⚠️ waarschijnlijk vervangen door 08-01/08-02 versies |
| 2026-08-03 06:00 | get_file_inflow timezone bug | `legacy.get_file_inflow` (gefixt) | [ ] |

## nog te doorzoeken (ouder dan bovenstaande lijst)
Zoek in oudere chats op onderwerp met `conversation_search`:
- FlowBoard widget spec (FlowGrid, FlowContainer, FlowCards, FlowTable)
- distribution-bar control
- OEE / state_shift_agg / get_resource_state
- catalog.xbom / library_option / configurator json
- PrintFactory / Zünd / Durst integraties
- cart / outsourcing multi-tenant (`core.cart_relation`, `core.cart_event`)
- resource allocation ledger (`core.line_item_resource`)

## let op — mogelijke versieconflicten
- `mock.get_print_schedule_materials` is hernoemd naar `_test` op 2026-08-10 — check of de oudere versie (2026-08-09) nog ergens los rondzwerft
- printschema query van 2026-08-06 is mogelijk voorloper van de 2026-08-09 functie — alleen de laatste bewaren
