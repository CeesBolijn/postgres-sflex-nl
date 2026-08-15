# project conventions

Stack: PostgreSQL (owner `xfw3`), React 19.2, Tailwind 4.2, UntitledUI/react, Figma MCP.

## algemeen
- altijd de simpelste, kortste oplossing
- semantiek in data, niet in code — business logic in JSON, niet hardcoded
- generieke componenten, geen speciale gevallen in code
- geen kolom of key genaamd `id` — altijd beschrijvend (`nest_group_id`, `resource_uid`, ...)
- geen aannames — vragen bij twijfel

## sql
- functies altijd met schema-naam (`mapping.crud_ticket`), ook bij `ALTER FUNCTION ... OWNER TO xfw3`
- crud-functies altijd set-based: geen FOR loop, geen temp table
  gebruik `jsonb_array_elements(p_param_json) AS el`, velden via `(el->>'field')::type`
- `ON CONFLICT DO UPDATE`: alleen `EXCLUDED.*`, nooit `rec.*`
- `RETURNS TABLE`: eerste regel na `AS $$` is altijd `#variable_conflict use_column`
- comments in sql altijd in het engels
- breaks/non-working-time rekken de job op (nooit losse spacer-rows)
- non_working_times gaan als JSON naar de frontend/timeline; nooit server-side start/duur berekenen

## json
- snake_case voor keys, kebab-case voor code-waardes
- `i18n` (niet `ml`) voor meertalige blokken
- `template` (niet `text_formula`) voor template strings
- bij "code" als hoofd-key: property `content` voor alle tekst, plus een property voor wat je maakt

## lookup json
- de inhoud van een lookup staat in `json/lookup/<schema>/<lookup>.json`
- de map is het schema, de bestandsnaam is de lookup-naam, het bestand bevat de `lookup_json` zelf
- voorbeeld: `SELECT lookup_json FROM production.lookup WHERE lookup = 'lookup_nest_moments'`
  staat in `json/lookup/production/lookup_nest_moments.json`
- schrijf of herschrijf je een functie die `lookup_json` leest en het bestand staat er niet:
  vraag of het toegevoegd wordt, nooit zelf de inhoud verzinnen

## data_group json
zie `docs/data-group-governance.md` voor de volledige analyse

- een key heeft overal dezelfde vorm — een lijst blijft een lijst, ook met één element
  (`children`, `hidden_when`, `src` zijn altijd een array)
- config-keys staan nooit tussen veldnamen: `field_config` bevat alleen velden,
  layout-keys als `class_name` staan ernaast
- `ui.type` zegt wat de waarde ís, `ui.control` hoe hij getoond wordt
- één tekst-slot in `i18n`: `title` (niet `text` of `label`); `subtitle` alleen bij een echte tweede regel
- `<naam>_field` betekent "de naam van een veld", zonder suffix is het de waarde zelf
- eenheid in de key, niet in een aparte property: `duration_in_seconds`, niet `duration` + `unit`
- percentages altijd `_percentage` (niet `_perc`, `_pct`, `_percent`)
- één conditie-vorm: `{field, op, value}`, vergelijk je twee velden dan `value_field`
- sorteren: `sort: {field, direction}`; groeperen: `group_by`, altijd een array
- chart-config keys heten `<chart>_chart_config`, varianten zijn properties of een prefix
  (`stacked_bar_chart_config`), geen losse key per variant
- booleans met `no_*` / `hide_*` staan default op false

## overig
- titels: alleen eerste woord met hoofdletter
- geen technisch jargon, korte uitleg
