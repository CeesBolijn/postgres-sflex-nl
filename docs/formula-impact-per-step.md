# production_impact in het manifest

Datum: 2026-08-26. Hoort bij `docs/imposition-unit-manifest.md`.

## de regel

**Elke manifestregel vult `production_impact_per_unit` met wat híj toevoegt.**
De lezer telt op:

```sql
sum(production_impact_per_unit * amount)
```

Meer is het niet. Geen max, geen totaliser, geen speciaal geval voor meerdere
printmethodes.

## de gangen

Printen gaat in gangen over hetzelfde vel. Er zijn er drie soorten, en de naam
van de optiecode zegt hoeveel je er van elk nodig hebt:

| option_code | fc | w | neon |
|---|---|---|---|
| `print-method.full-color` | 1 | | |
| `print-method.full-color-full-color` | 2 | | |
| `print-method.full-color-full-color-full-color-full-color` | 4 | | |
| `print-method.full-color-neon` | 1 | | 1 |
| `print-method.full-color-white` | 1 | 1 | |
| `print-method.full-color-white-full-color` | 2 | 1 | |
| `print-method.full-color-white-neon` | 1 | 1 | 1 |
| `print-method.full-color-white-white` | 1 | 2 | |
| `print-method.full-color-white-white-neon` | 1 | 2 | 1 |
| `print-method.white` | | 1 | |
| `print-method.white-white` | | 2 | |

Tel de delen in de naam en je hebt de rij.

`fc`, `w` en `neon` zijn de prijs van één zo'n gang over dit vel. Meer variabelen
zijn er niet nodig: `fc2` is `2 * fc`, `fc4` is `4 * fc`, `w2` is `2 * w`.

## de formules

Twee soorten regels per code. Eerst wat je toevoegt, dan wat er nu gedaan is:

```
production_impact_per_unit = max(<nodig> - <gedaan>, 0) * <gangprijs>
<gedaan> = max(<gedaan>, <nodig>)
```

`max(nodig - gedaan, 0)` is precies de check die je beschreef: is de gang er al,
dan is het verschil 0 en kost hij niets; is hij er nog niet, dan komt hij erbij.
Voor `fc4` naast een al gedane `fc2` levert dat vanzelf twee gangen op.

De elf arrays, klaar om te plakken:

```json
print-method.full-color
["production_impact_per_unit = max(1 - fc_done, 0) * fc",
 "fc_done = max(fc_done, 1)"]

print-method.full-color-full-color
["production_impact_per_unit = max(2 - fc_done, 0) * fc",
 "fc_done = max(fc_done, 2)"]

print-method.full-color-full-color-full-color-full-color
["production_impact_per_unit = max(4 - fc_done, 0) * fc",
 "fc_done = max(fc_done, 4)"]

print-method.white
["production_impact_per_unit = max(1 - w_done, 0) * w",
 "w_done = max(w_done, 1)"]

print-method.white-white
["production_impact_per_unit = max(2 - w_done, 0) * w",
 "w_done = max(w_done, 2)"]

print-method.full-color-neon
["production_impact_per_unit = max(1 - fc_done, 0) * fc + max(1 - neon_done, 0) * neon",
 "fc_done = max(fc_done, 1)",
 "neon_done = max(neon_done, 1)"]

print-method.full-color-white
["production_impact_per_unit = max(1 - fc_done, 0) * fc + max(1 - w_done, 0) * w",
 "fc_done = max(fc_done, 1)",
 "w_done = max(w_done, 1)"]

print-method.full-color-white-full-color
["production_impact_per_unit = max(2 - fc_done, 0) * fc + max(1 - w_done, 0) * w",
 "fc_done = max(fc_done, 2)",
 "w_done = max(w_done, 1)"]

print-method.full-color-white-white
["production_impact_per_unit = max(1 - fc_done, 0) * fc + max(2 - w_done, 0) * w",
 "fc_done = max(fc_done, 1)",
 "w_done = max(w_done, 2)"]

print-method.full-color-white-neon
["production_impact_per_unit = max(1 - fc_done, 0) * fc + max(1 - w_done, 0) * w + max(1 - neon_done, 0) * neon",
 "fc_done = max(fc_done, 1)",
 "w_done = max(w_done, 1)",
 "neon_done = max(neon_done, 1)"]

print-method.full-color-white-white-neon
["production_impact_per_unit = max(1 - fc_done, 0) * fc + max(2 - w_done, 0) * w + max(1 - neon_done, 0) * neon",
 "fc_done = max(fc_done, 1)",
 "w_done = max(w_done, 2)",
 "neon_done = max(neon_done, 1)"]
```

Snijmethodes zijn geen geneste gangen. `kiss-cut` en `through-cut` zijn twee
losse bewerkingen, dus die kijken nergens naar:

```json
["production_impact_per_unit = kiss_cut_seconds"]
```

## nagerekend

Read-only door de echte evaluator gehaald, met 120 s per gang. De som is altijd
het aantal gangen × 120:

| codes op de impositie | per regel | som | gangen |
|---|---|---|---|
| `fc` | 120 | 120 | 1 |
| `fc-2w` | 360 | 360 | 3 |
| `fc` + `fc-2w` | 120, 240 | 360 | 3 |
| `fc` + `fc-neon` | 120, 120 | 240 | 2 |
| `fc` + `fc-w` + `fc-2w` | 120, 120, 120 | 360 | 3 |
| `fc-2w` + `fc-neon` | 360, 120 | 480 | 4 |
| `fc-neon` + `fc-2w` | 240, 240 | 480 | 4 |
| `2w` + `fc-w` | 240, 120 | 360 | 3 |
| `fc` + `fc2` + `fc4` | 120, 120, 240 | 480 | 4 |
| `fc4` + `fc` | 480, 0 | 480 | 4 |

De laatste twee paren laten het belangrijkste zien: **de som hangt niet van de
volgorde af.** `formula_level` bepaalt alleen wie de gang op zijn conto krijgt.
Zet de codes met de minste gangen op het laagste level, dan leest het manifest
het prettigst.

Meerdere printmethodes op één impositie komen bijna nooit voor — 82 van de
~10 000 nesten per week. De formules moeten er alleen niet op stuklopen, en dat
doen ze niet.

## waar de stap vandaan komt

Er komt **geen** `step`-kolom op het manifest. De stap hangt aan het item:

```
manifestregel.item_code
  -> catalog.item.item_group_code
  -> catalog.item_group.possible_status_sequence
  -> relation.lookup 'lookup_step_category'   (sequence -> step)
```

`lookup_step_category` geeft de stappen op volgorde: `impose` 500, `rip` 600,
`print` 700, `calander` 710, `coat` 790, `laminate` 795, `apply` 797,
`route` 798.

Twee dingen zijn daarvoor nog niet gevuld, en dat staat los van dit plan:
`catalog.item_group` heeft één rij (`material`) met een lege
`possible_status_sequence`, en de elf `print-method`-regels in de xbom hebben
geen `item_code`. Optellen kan dus al wel; uitsplitsen per stap nog niet.

## twee valkuilen in de evaluator

Read-only gemeten, allebei het soort fout dat je pas ziet als de getallen al
fout zijn.

**Een onbekende variabele laat de hele evaluatie klappen** — geen 0, maar een
foutmelding:

```
["e = u + 1"]  zonder u   ->  ERROR
["e = u + 1"]  met u = 0  ->  {e: 1}
```

Daarom krijgen `fc_done`, `w_done` en `neon_done` vooraf de waarde 0. Dat doet
de functie, niet de formuleschrijver.

**Een ternary slikt alles wat erachter staat.** `a > 0 ? a : b + c` wordt
gelezen als `a > 0 ? a : (b + c)`. Met `fc = 5` en `w = 7` geeft
`fc > 0 ? fc : 100 + w` de waarde **5**, en `(fc > 0 ? fc : 100) + w` de waarde
**12**. Met `max()` hierboven heb je geen ternary nodig; komt er ooit een, zet
hem tussen haakjes.

## hoe het draait

De regels van één impositie worden op `(formula_level, sort_order)` achter
elkaar geëvalueerd. De variabelen gaan van regel naar regel mee, en na elke
regel wordt `production_impact_per_unit` weggeschreven.

De opslagregel is algemeen: **een variabele met de naam van een kolom gaat naar
die kolom, de rest blijft in `param_json`.**

## wie wat doet

**Jij:** de elf arrays hierboven in de formula_editor, de `formula_level` per
code (minste gangen eerst), de snijformules, en waar `fc`, `w` en `neon` hun
seconden vandaan halen.

**Ik:** het seeden op 0, het vouwen op `(formula_level, sort_order)`, het
wegschrijven per regel, en `sum(production_impact_per_unit * amount)` in
`get_impose_plan`.

## verder

De optiecodes van een impositie komen uit de orderregels via
`catalog.get_xbom_grouping_keys`. `nest_json` speelt geen rol — die vervalt, dus
alleen de xbom en de manifests blijven over.
