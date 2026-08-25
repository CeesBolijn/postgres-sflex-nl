# Nestplanning en lane items

**Elk gepland moment is een echt lane item, ook in de toekomst.** De template
(`mock.material_impose_plan`) stempelt lane items; daarna zijn de lane items de
waarheid die de borden lezen en de client muteert. Elke clientmutatie schrijft
door naar de template, zodat opnieuw stempelen dezelfde planning oplevert.

Stand: 2026-08-24, geverifieerd tegen de database.

## kernbegrippen

| ding | wat |
|---|---|
| `mock.material_impose_plan` | weekpatroon, één rij per gepland moment. Sleutel van een lane: `weekday` + `step` + `resource_path` + `material_id` + `instance` |
| `resource_path` | wijst naar een impose-resource (`dk.sheet.impose.320`) — imposeren gebeurt per materiaalbreedte, niet per printer |
| `action.lane_item` | het gestempelde moment. `source = 'material-plan'`, `source_ref = '<plan_id>:<datum>'` (uniek) |
| `action.imposition_group_lane_item` | wat het moment produceert. `imposition_group_id` = **alias van `material_id`** tot de xbom-groepen er zijn |
| `action.nest_lane_item` | de nests die echt gemaakt zijn, per lane item |

**Elke patroonrij is één lane.** Een tweede moment voor hetzelfde materiaal is
dus een tweede lane (`instance` 1). De borden renderen dat verschillend:
nest_schedule zet elk record op zijn eigen rij, nest_resource_schedule en
production_schedule groeperen records op resource/lane.

## stappen

### 1. opruimen — klaar
Dateloze lanes weg, `lane_date not null`, `production_orderline_lane_item`
gedropt. (`sql/migration_lane_slots.sql`)

### 2. stempelen — klaar
`mock.generate_plan` maakt per patroonrij een lane + lane item + groeplink.
650 items, allemaal in de toekomst, duratie 0.

### 3. impose-resources + hernoemen — te draaien
- `sql/migration_impose_resources.sql` — 17 impose-resources, afgeleid uit de
  printerpaden (`site.material.impose.width`).
- `sql/migration_material_impose_plan.sql` — tabel → `material_impose_plan`,
  `copy_index` → `instance`, `resource_uid` → `resource_path`.
- direct daarna: `sql/mock/crud_material_impose_plan.sql`,
  `generate_plan.sql`, `get_print_schedule_materials.sql`.

### 4. crud_lane_item — te bouwen
`sql/action/crud_lane_item.sql`, één crud voor alle clientmutaties, altijd
write-through naar de template:

| gebaar | lane item | template |
|---|---|---|
| verplaatsen | `start_offset_in_seconds` | zelfde rij bijwerken |
| sorteren | `sort_order` | zelfde rij bijwerken |
| pinnen | `is_pinned` | zelfde rij bijwerken |
| kopiëren | nieuwe lane + item | nieuwe rij, volgende `instance` |

### 5. nests koppelen — klaar
`legacy.crud_nest` resolvet plan → lane → lane item via de groeplink en vult
`action.nest_lane_item`. Backfill gedaan: 13477 links.

### 6. de reads — half
`get_nest_schedule` leest lane items en nest-links; `get_print_schedule_materials`
draait nog op de oude weg. Te doen:
- print-read op lane items zetten;
- beide de groeplink laten gebruiken in plaats van de material-omweg;
- `mock.material_resource_plan_lane` droppen (overbodig: `source_ref` draagt
  dezelfde link);
- per lane item `first_item_duration` en `batch_duration` teruggeven
  (rekentijd, niets opslaan).

### 7. ketening — volgt op 6
`next_start_offset_in_seconds` en de trigger-enum vervallen. Twee properties op
de impose-resource:

- `next_start_after_first_item` — 0/1, afwezig = na de hele batch;
- `next_start_lag_in_seconds` — extra wachttijd, imposeren staat op 900.

```
next_start_offset = (1 - next_start_after_first_item) * batch_duration
                  + next_start_after_first_item * first_item_duration
                  + next_start_lag_in_seconds
```

Geen branches: de frontend ketent zelf, met het connector-mechanisme van
`plan_timeline`. Migratie van de oude waardes: `batch_duration` → niets,
`first_item_duration` → `1`, `after_lag` → `1` + lag. Omschakelpunten:
`get_plan_timeline`, `get_resource_plan_batch`, en in de data_groups vervangt
het connector-blok `next_start_offset_in_seconds_field`.

### 8. echte impositiegroepen — later
Stempelen en nestresolutie schakelen van de material-alias naar
`catalog.get_imposition_group` (de xbom-paden). Elke alias-join draagt een
comment die het omschakelpunt markeert.

## besloten

- Meerdere lane items per groep per dag tonen **dezelfde** aggregaatcijfers —
  een duplicaat is een planningsmoment, geen verdeling van het werk.
- De toekomstkant blijft een aggregaat, berekend bij lezen. Niets afgeleids
  wordt opgeslagen.
- `instance` blijft server-side; het drag & drop-contract verandert niet.
- `mock.material_impose_plan` blijft in `mock.` tot een ander
  template-mechanisme hem vervangt.

## open

- **Mutatie-identiteit van nest_schedule.** `set_group_fields` is nu
  `["tenant_id","material_id","production_line_id"]` en wordt dubbelzinnig
  zodra een materiaal twee lanes heeft. Kiezen: `lane_id` erbij (zoals
  production_schedule) of `instance` erbij (blijft geldig na opnieuw
  stempelen).
- **Plan-type-string.** `action.plan.type = 'material-resource-plan'` blijft
  voorlopig zo; hernoemen naar `material-impose-plan` is een data-update.
