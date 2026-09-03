# handoff: OEE-charts — wat de frontend moet kunnen

Voor de Claude Code-sessie in de frontend-repo. De data-kant (functies,
lookups, data_groups) is af en gedraaid; dit zijn de widget-features die de
config verwacht. Alle voorbeelden komen letterlijk uit de data_groups
`resource_oee_area_chart` (62), `resource_oee_chart` (29) en
`resource_oee_timeline` (19).

## 1. de platte lookup-vorm

`log.lookup / lookup_resource_state` is één platte array; per node:

```json
{
  "code": "producing",
  "i18n": { "nl": { "title": "Producing" }, "en": { "title": "Producing" } },
  "group": "state",
  "order": 190,
  "class_name": "state-producing",
  "fill": "var(--state-producing)",
  "color": "var(--state-producing-color)",
  "counts_as": "producing",
  "alias_of": "starved"
}
```

- `i18n` staat direct op de node — geen `block`-wrapper, geen `title`-kopie.
- `fill`/`color` zijn complete css-`var(...)`-expressies uit
  `docs/css_variables.css` (staat in de frontend als stylesheet): `fill` is de
  svg-fill van vlak/segment/balk, `color` de tekstkleur erop. Eén-op-één in de
  style zetten, niet parsen. Sommige hebben een fallback:
  `var(--state-available, transparent)`.
- `class_name` blijft bestaan voor niet-svg styling.
- `counts_as` en `alias_of` zijn server-side verwerkt; de frontend hoeft er
  niets mee.

## 2. stacked-area-chart (data_group 62)

De functie levert per (datum × groep) rijen per state plus één synthetische
`available`-rij; de stapel sluit áltijd exact op het venster.

| config-key | waarde | wat de widget moet doen |
|---|---|---|
| `y_field` | `duration_seconds` | y-waarde in seconden |
| `y_axis` | `{"format": "hh:mm", "begin_at_zero": true, "max_field": "param_json.total_shift_in_seconds"}` | **nieuw op deze widget**: as-labels als uu:mm; vaste y-max uit het veld (venster: 64.800 s werkdag, 32.400 s weekend) — de as schaalt níét mee met de data |
| `set_field` | `counts_as` | serie-indeling op deze platte kolom (jsonb-paden werken hier niet, dat was de bug "alles in één naamloze set") |
| `set_order_field` | `sort_order` | stapelvolgorde, laag = onder: producing (190) → verliezen (230–270) → available (275) → breakdown (280) → offline (300) |
| `fill_field` / `color_field` | `state_json.fill` / `state_json.color` | **nieuw**: svg-fill en tekstkleur per serie, waarde is een `var(...)`-string |
| `class_names_field` | `state_json.class_name` | enkel string-pad, bestaande feature |
| `set_overrides.planned` | `{"type": "line", "stacked": false}` | de planning als losse lijn, niet in de stapel |
| `set_overrides.available` | `{"no_legend": true, "no_tooltip": true}` | **nieuw**: de serie wordt getekend (de band die de stapel sluit) maar verschijnt niet in de legenda en niet in de tooltip |
| geen `set_title_field` | — | geen titel boven de chart |

Tooltip: header over twee regels (regel 1 `shift_date` + `step`, regel 2
`param_json.total_shift_hours` + `oee_json.producing_oee` als `percent` — de
spans vullen per paar de gridregel); daaronder één sectie met per staterij
`state` + `duration_seconds` (`duration`, `hh:mm`). Geen aparte
samenvattingssectie: "niet beschikbaar" is een gewone staterij.

De functie levert twee synthetische states: `available` (de kleurloze
middenband; `no_legend`/`no_tooltip` via `set_overrides`) en `unavailable`
(bovenin de stapel: de breakdown/offline-tijd die níét als eigen vlak
geselecteerd is; de rij ontbreekt als de selectie alles al dekt). Beide
gedragen zich verder als elke andere state.

Betekenis van de tooltipwaarden:

- `total_shift_hours` — het venster: de som van de shiftlengtes (18,0 werkdag,
  9,0 weekend), de vaste bovenkant van de chart.
- `unavailable_hours` ("niet beschikbaar") — `breakdown_hours +
  offline_hours`: de uren dat de machine er niet kón zijn. Dit is wat vóór de
  OEE-deling van het venster afgaat.
- `producing_oee` — `producing_hours / (total_shift_hours −
  unavailable_hours) × 100`.
- de `available`-band (geen tooltipwaarde meer) is een restwaarde: venster
  minus alles wat als vlak getoond wordt; hij beweegt mee met de filterselectie.

## 3. donut (data_group 29)

- `fill_field: "state.fill"`, `color_field: "state.color"` — zelfde contract
  als hierboven.
- `content_field: "state.i18n"` — i18n direct op de node.
- `class_names_field: "state.class_name"` — enkel string-pad.

## 4. timeline (data_group 19)

- `class_names_field: "state.class_name"` — enkel string-pad (geen array).
- lane-volgorde komt uit `set_order_field: "state.order"`; alle
  `group: "plan"`-codes hebben orders 10–180, machine-states 190–310, dus de
  plan-lane hoort boven de state-lane te sorteren, welke kant van de set de
  widget ook pakt.
- `group_by: ["resource_uid"]` op `timeline_config`.
- tooltip-paden zijn `state.i18n` / `group_state.i18n` (geen `block` meer).

## 5. css

`docs/css_variables.css` is de bron van alle kleuren. Nodig in de stylesheet:

- `--state-available` (+ `-color`) — de middenband; ontbreekt hij, dan valt de
  lookup terug op `transparent`, wat ook prima is.
- klasse `state-available` voor de niet-svg-kant van diezelfde band.
- `--state-blocked-operator` bestaat niet; de lookup valt terug op
  `--state-blocked`. Toevoegen mag, hoeft niet.

## 6. wat er níét meer is

- `color`-property in de lookup (vervangen door `fill`/`color` met css-vars)
- `state.block.i18n`-paden (i18n direct op de node)
- `duration_percent`, `parent_percent`, `total_duration_seconds` in de
  functie-output van 62 (nu `duration_percentage`, `param_json`, `oee_json`)
- `normalized`/`y_height: 100` op de area-chart (de y-as is uren met een vaste
  max uit `max_field`)
