# Lookups: block eruit, i18n direct op de node

Status: plan. De nieuwe vorm is `{ "code": ..., "i18n": {...}, ... }`; de oude
wrapper `{ "block": { "i18n": {...}, "title": "..." } }` moet overal weg.
De frontend leest al de nieuwe vorm — hoe korter de oude nog leeft, hoe beter.

## 1. inventaris (DB-scan 2026-08-24, alle negen lookup-tabellen)

| lookup | aantal block-nodes |
|---|---|
| legacy.lookup_rework | 2 |
| legacy.lookup_shift | 3 |
| legacy.lookup_time_on_status | 2 |
| legacy.lookup_trend | 4 |
| relation.lookup_resource_state | 30 |
| site.lookup_profile_state | 3 |

Geen van de zes heeft een repo-mirror in `json/lookup/` (daar staan alleen
`lookup_nest_moments`, `lookup_step_category`, `lookup_tenants`) — die mirrors
komen er bij deze migratie meteen bij, conform de lookup-conventie.

## 2. de transformatie

Per node, recursief door het hele document (nodes zitten ook genest in
`states`-arrays):

```
{ ..., "block": { "i18n": {...}, "title": "..." } }
→ { ..., "i18n": {...} }
```

`block.title` vervalt (de i18n is de bron). Eén migratiescript met een
tijdelijke recursieve helper (`pg_temp.strip_block(jsonb)`): object met
`block` → `(j - 'block') || jsonb_build_object('i18n', j->'block'->'i18n')`,
daarna alle values recursief; arrays elementsgewijs. Daarna per tabel:

```sql
update <schema>.lookup
set lookup_json = pg_temp.strip_block(lookup_json)
where lookup_json::text like '%"block"%';
```

Optioneel meeliften: `lookup_resource_state` krijgt in dezelfde rewrite de
`counts_as`-property uit het OEE-voorstel (zelfde lookup, één omzetmoment).

## 3. de lezers die tegelijk mee moeten

Geverifieerd op echte `->'block'`-toegang (prosrc-scan + repo):

| lezer | wijziging |
|---|---|
| `legacy.get_resource_shift_employees` | `item->'block'->'i18n'` → `item->'i18n'` (`sql/legacy/get_resource_shift_employees.sql:25`) |
| `mapping.get_status_bar_rework` | `grp->'block'->'i18n'` → `grp->'i18n'` (`sql/mapping/get_status_bar_rework.sql:18`) |
| `mapping.get_status_bar_time_on_status` | idem (`sql/mapping/get_status_bar_time_on_status.sql:26`) |
| trend-keten | `mapping.get_internal_rework_trend_by_production_line` en `get_ticket_trend_by_production_line` geven de `lookup_trend`-entry ongewijzigd door als `r_trend_block` — de functies zelf hoeven niet om, maar de **data_groups** `internal_rework_trend` en `ticket_trend` lezen er `block.i18n`-paden uit: die worden `…i18n` |
| data_groups `resource_oee_timeline`, `resource_oee_chart` | matchen op "block" in de DB-scan — nalopen welke paden dat zijn en omzetten |
| frontend (control-room) | state-timelines lezen de nodes van `lookup_resource_state`; leest al de nieuwe vorm — check dat er geen block-fallback meer nodig is |

**Bewust níet aanpassen** (false positives uit de scan):
`site.search_product` leest `product_json->'block'` — geen lookup;
`site.get_blocks`/`get_page_*` gaan over het `site.block`-paginasysteem;
`'blocked'`-statecodes en "block"-comments in `get_plan_timeline`,
`get_resource_state_shift_totals`, `mock.*` zijn tekst-toevalstreffers.

## 4. nav- en data-bestanden in de repo

Dezelfde wrapper leeft ook buiten de lookups:

- `json/data/nav/app-nav.json` — `text_field: "block.i18n"` (2×) én
  block-objecten op de menu-items → `i18n` direct;
- `json/data/nav/menu-items.json`, `json/data/nav/models.json` —
  block-wrappers per item/model strippen;
- het glossary-voorstel (`docs/plan-field-glossary.md`, laag 3) gebruikte
  `block.i18n` als vorm voor card-uitleg — wordt `i18n` direct op de
  layout-node.

## 5. volgorde

1. **Eén omzetmoment**: de lookup-migratie + de drie aangepaste functies +
   de data_group-updates (trend ×2, oee ×2, partial) + de nav-bestanden.
2. **Mirrors vastleggen**: de zes lookups na de migratie exporteren naar
   `json/lookup/<schema>/<lookup>.json`.
3. **Conventie**: entry in `rename-map.json` (`block` → weg, `i18n` direct)
   en een regel in CLAUDE.md/data-group-governance: geen `block`-wrapper
   meer in lookup_json en nav-data; `i18n` staat direct op de node.
