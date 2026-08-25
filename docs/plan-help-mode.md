# Help-modus: on_help als navigatie

Status: voorstel. Vervangt het glossarium-voorstel (uitleg als tooltip per
veld) — uitleg is geen veldeigenschap maar een **bestemming**: een sidebar of
venster met echte inhoud.

Aanleiding: "Delen" is als kolomkop te mager, en er is nergens plek om uit te
leggen wat een kaart toont of hoe er geteld wordt.

## het gebaar

1. Een help-icoon in de header, naast account (`json/data/nav/app-nav.json`).
2. Klik erop → **help-modus aan**: helpbare elementen lichten op, de rest
   dimt, de cursor wordt een vraagteken.
3. Klik op een element → de dichtstbijzijnde `on_help` wordt uitgevoerd →
   navigatie naar de helpbestemming → **modus meteen weer uit** (eenmalig,
   zoals een pipet).
4. Esc of nogmaals op het icoon → modus uit zonder actie.

In help-modus voert een klik **nooit** de onderliggende actie uit: geen
selectie, geen drag, geen crud.

## het contract

`on_help` staat naast `menu` en `on_select` in `row_options.nav` en heeft
dezelfde vorm als een menu-item — `path` plus `params`, zodat de bestemming
context meekrijgt:

```json
"row_options": {
  "nav": {
    "on_help": {
      "path": "(sidebar:help)",
      "params": [
        { "key": "topic", "default_value": "nest-schedule-lane" },
        { "key": "material_id", "value_from": "material_id", "is_query_param": true }
      ]
    }
  }
}
```

**Overerving** — anders moet alles geannoteerd worden. De frontend zoekt bij
een klik omhoog en gebruikt de eerste `on_help` die hij tegenkomt:

```
element → container/card → data_group → pagina (pages.json)
```

Eén `on_help` op de pagina dekt dus alles; je verfijnt alleen waar het echt
anders is. Vindt hij niets, dan blijft de modus aan en zegt de UI dat er voor
dit element geen uitleg is (niet: stilzwijgend niets doen).

## de inhoud

Eén bestemming, gevoed uit een lookup — geen tweede plek waar uitleg woont:

- `site.lookup` → `lookup_help_topics`, repo-mirror
  `json/lookup/site/lookup_help_topics.json`;
- per topic-key een `i18n`-blok **direct op de node** (geen `block`-wrapper,
  zie `docs/plan-lookup-block-i18n.md`) met `title` en `description`;
- `site.get_help_topic(p_topic text)` + data_table `get_help_topic`;
- data_group `help_topic` en een pagina `help` in `pages.json`, zodat
  `(sidebar:help)` een gewone pagina is en geen speciaal geval.

Voorbeeld-entry:

```json
{
  "topic": "nest-schedule-lane",
  "i18n": {
    "nl": {
      "title": "Lane in de nestagenda",
      "description": "Eén rij per materiaal en gepland moment. Delen zijn productdelen: een unit kan uit meerdere delen bestaan die apart genest en gesneden worden — de kolom verschijnt alleen als hij afwijkt van Units."
    }
  }
}
```

## waarom geen tooltips per veld

Overwogen en laten vallen: een `description`-slot per veld plus een centraal
veldglossarium. Het levert twee systemen op die allebei uitleg bevatten, en
uitleg van een kolomkop is zelden genoeg — de vraag is meestal "wat toont dit
blok en hoe wordt er geteld", niet "wat betekent dit woord". Eén bestemming
met echte inhoud is beter dan honderd korte tooltips.

## uitrol

1. **Frontend** (control-room): help-icoon, modus, overerving en het
   uitvoeren van `on_help` — zie de prompt onderaan.
2. **Lookup + functie + data_table**, pagina `help` in pages.json, data_group
   `help_topic`.
3. **`on_help` toevoegen** waar het meeste gevraagd wordt: pagina-niveau
   eerst (dekt alles), daarna de borden die uitleg verdienen.
4. **Conventie** in CLAUDE.md: `on_help` hoort bij `nav`, is altijd
   navigatie, en helpinhoud staat in `lookup_help_topics`.

## prompt voor het control-room-project

```text
Bouw een help-modus met een nieuw nav-type `on_help`.

## Gebaar
- Zet een help-icoon (vraagteken) in de top-header, naast account.
- Klik erop → help-modus aan. In die modus: helpbare elementen krijgen een
  duidelijke highlight, de rest dimt, de cursor wordt `help`.
- Klik op een element in help-modus → voer zijn `on_help` uit (navigatie) en
  zet de modus meteen weer uit. Eenmalig, zoals een pipet.
- Esc of nogmaals op het icoon → modus uit zonder actie.
- In help-modus voert een klik NOOIT de onderliggende actie uit: geen
  selectie, geen drag & drop, geen crud, geen menu.

## Contract
`on_help` staat naast `menu` en `on_select` in `row_options.nav` en heeft
exact de vorm van een menu-item: `path` + `params` (met `value_from`,
`default_value`, `is_query_param` zoals overal).

  "row_options": {
    "nav": {
      "on_help": {
        "path": "(sidebar:help)",
        "params": [
          { "key": "topic", "default_value": "nest-schedule-lane" },
          { "key": "material_id", "value_from": "material_id",
            "is_query_param": true }
        ]
      }
    }
  }

## Overerving
Bij een klik zoek je omhoog naar de eerste `on_help` die je tegenkomt:
element → container/card → data_group → pagina. Eén `on_help` op de pagina
dekt dus alles. Vind je niets, laat de modus dan AAN staan en meld in de UI
dat er voor dit element geen uitleg is — nooit stilzwijgend niets doen.

## Verder
- Volledig generiek: niets in de component mag over een specifiek bord of
  veld gaan; alles komt uit de nav-config.
- De bestemming is een gewone pagina/sidebar (`(sidebar:help)` bestaat in
  pages.json), geen speciaal geval in code.
- Toetsenbord: het help-icoon is focusbaar en met Enter te activeren; in
  help-modus is Esc altijd de uitgang.
- Respecteer `prefers-reduced-motion` bij de highlight-animatie.
```
