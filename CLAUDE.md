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

## overig
- titels: alleen eerste woord met hoofdletter
- geen technisch jargon, korte uitleg
