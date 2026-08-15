# Overdracht naar control-room

Wat de React-kant moet weten na de wijzigingen aan de nest-borden en de
data_group-json van augustus 2026. Bron van waarheid blijft
`json/data_group/*.json` (en de export `xfw3_site_data_group.json`, die met
`sql/update_data_group.sql` in `site_data_group` wordt gezet).

## 1. `fields_class_name` — nieuwe key, renderer moet hem lezen

De class die vroeger in `field_config` stond (en daarna als `class_name`
naast `field_config`) heet nu **`fields_class_name`**. Overal waar een blok
een `field_config` heeft: blok, tooltip-sectie, `group`, `label_options`.

| key | op | betekent |
|---|---|---|
| `fields_class_name` | een blok met `field_config` | de grid waarin de velden gerenderd worden (`grid grid-cols-6 gap-1`) |
| `ui.class_name` | een veld | de class van de cel van dat veld (`col-span-3 text-right`) |
| `class_name` | een element zelf (`row_options.class_name`) | de class van dat element |

79 plekken, allemaal in `rename-map.json` onder `keys` (`class_name →
fields_class_name`). Een renderer die nog `class_name` naast `field_config`
leest, rendert de velden zonder grid.

## 2. Container queries — classes die moeten bestaan

`nest_schedule` en `nest_resource_schedule` gebruiken container queries: de
kaart en de tooltip meten hun eigen breedte, niet het scherm.

- `fields_class_name`: `@container grid grid-cols-6 gap-1`
- velden: `col-span-6 @xs:col-span-2`, `col-span-2 text-right`,
  `col-span-3 @sm:col-span-2`, `col-span-6`

Tailwind genereert alleen classes die het als tekst in de frontend-bronnen
tegenkomt; de data_group-json staat in de database. **Nieuw** ten opzichte van
wat al in gebruik was: `@xs:col-span-2` en `@sm:col-span-2`. Safelist in de
css, dan kan de json vrij spannen:

```css
@source inline("{@xs:,@sm:,@md:,@2xl:,}col-span-{1..12}");
```

Volledige uitleg (breakpoints, container-schaal, recept):
`docs/data-group-layout.md`.

## 3. Nest-borden: andere velden

`mock.get_nest_schedule` levert andere kolommen; de twee data_groups (76 en
78) zijn daarop aangepast. Alleen relevant als de client ergens veldnamen
hardcodet — de config zelf is generiek.

| weg | ervoor in de plaats |
|---|---|
| `actual_sqm` | `sqm` (= werkelijke inflow; was forecast/actual-mix) |
| `param_json.specs.actual_panels`, `param_json.specs.forecast_panels` | `param_json.specs.amount` (sheets, of meters bij rol) |
| `max_panels`, `min_panels` | vervallen |
| `status_json` | vervallen; de bar leest `part_status_json` |

Nieuw op de rij: `orderline_count`, `product_amount`, `part_amount`,
`amount`, `forecast_sqm`, `rework_count`, `rework_sqm`, `gross_sqm`,
`part_status_json`, `nest_ids`, `nest_count`, `seconds_to_logistics_date`,
`class_names`, `unit_class_names`, `production_company_id`.

- `part_status_json` wordt getoond met de bestaande control
  `distribution-bar` (zelfde `distribution_bar_config` als production_board:
  `value_field: amount`, `class_names_field: class_names`, sort op `sequence`).
- `class_names` op de rij: `plan-alert` / `plan-signal` (nog niet genest,
  binnen resp. buiten 2 uur van `nest_date`), `plan-rework`, `state-delayed`;
  unie van alle orderregels van de rij, geen tellingen.
- `nest_ids` / `nest_count` zijn de nests op de lane_items van de lane, niet
  die van de orderregels.
- rijen zonder `material_id` én zonder `resource_uid` (spacers/noop) zijn
  ongewijzigd: de client handelt die af zoals nu.
- `label_options`, `set_group_fields`, drag-config: ongewijzigd, dus het
  verschil tussen de twee borden is precies wat het was.

## 4. Niet veranderd, ter bevestiging

- `i18n.<lang>.title` blijft het enige tekst-slot (zie `rename-map.json`).
- Conditievorm `{field, op, value}`, `hidden_when` als lijst, `sort {field,
  direction}`, `group_by` als lijst — zoals in `rename-map.json`.
