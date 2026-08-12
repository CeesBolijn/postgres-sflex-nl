# Chats: weggooien of archiveren

Periode: 29 juli t/m 11 augustus 2026 (buiten projecten — verder terug dan 29 juli staat niks). Onderverdeeld in twee soorten: kan echt weg (geen technische inhoud, of eenmalig en al uitgevoerd), en kan pas weg nadat een item uit `inventory.md` is geoogst.

## kan direct weg — geen technische inhoud of niet Probo-gerelateerd
| datum | titel | reden |
|---|---|---|
| 2026-08-02 08:15 | Laptop uit slaapstand activeren | onderwerp niet gerelateerd |
| 2026-08-03 14:29 | Duplicate git branch conflict | eenmalig, opgelost, geen blijvend artefact |
| 2026-08-08 14:38 | Gamma abonnement opzeggen | onderwerp niet gerelateerd |
| 2026-08-04 14:16 | Proboview optiebomen — reactie op e-mail Wilco | zakelijke correspondentie, geen technisch artefact — bewaar los als je de e-mail nog nodig hebt, niet in de repo |

## kan direct weg — vraag beantwoord, geen blijvend artefact
| datum | titel | reden |
|---|---|---|
| 2026-07-29 05:54 | Postgres, VSCode en Git setup | algemeen advies, geen projectspecifieke output |
| 2026-07-30 16:27 | MySQL tabellen met specifieke kolommen zoeken | losse debug-vraag, klaar |
| 2026-07-30 21:00 | Join performance op text columns | algemene kennisvraag, geen code om te bewaren |
| 2026-07-31 10:20 | Materialen status bijwerken op basis van selectie | kleine UPDATE, al uitgevoerd |
| 2026-08-01 13:55 | Material code formatting and catalog update | eenmalige migratie, al uitgevoerd en gedownload |
| 2026-08-03 06:06 | Converting UTC time to Europe/Amsterdam timezone | ontwerpgesprek zonder eindbeslissing, overruled door de fix van 08-03 06:00 |
| 2026-08-07 07:57 | Overlapping break times detection | eenmalige check, geen structureel artefact |
| 2026-08-08 11:09 | Debugging order detail function replacement | vastgelopen op plak-probleem, niets opgeleverd |
| 2026-08-04 15:39 | HTML date en time picker voorbeelden | algemene referentie, niet Probo-specifiek |

## pas weggooien na oogsten — bevat nog te bewaren sql/json
Deze staan (deels) al in `inventory.md`. Zodra het bijbehorende bestand in de repo staat, mag de chat weg.

| datum | titel | let op |
|---|---|---|
| 2026-07-29 09:46 | Nest time scale met uurlijkse intervallen | waarschijnlijk vervangen door latere versie — check eerst 08-01/08-02 |
| 2026-07-30 17:02 | Normalizing library options in PostgreSQL | grote sessie, meerdere functies, nog niet geoogst |
| 2026-07-31 06:07 | Palletwissels per dag per resource | `legacy.get_nest_planning` uitbreiding |
| 2026-07-31 07:43 | Line items, specs en unit manifests | resource allocation ledger, nog niet geoogst |
| 2026-07-31 09:12 | OEE berekening en resource state structuur | json-ontwerp, nog geen sql |
| 2026-07-31 14:25 | MySQL query mapping tabel setup | `mapping.crud_product` |
| 2026-08-01 09:56 | Timeline view segments with time range filtering | mogelijk vervangen, check tegen 08-02/08-09 |
| 2026-08-02 09:31 | Nest-planning, get_nest_schedule | grote sessie — check eerst of 08-10/08-11 chat deze al vervangt |
| 2026-08-03 06:00 | Function debugging (get_file_inflow) | gefixte functie, nog niet geoogst |
| 2026-08-05 16:32 | PostgreSQL schaalbaarheid bij 40.000 dagelijkse orders | argumentatie voor intern document — bewaar tot dat document af is |
| 2026-08-06 06:42 | SQL query voor printschema's | mogelijk voorloper van latere versie, check eerst |

## laat nog even staan — actief in gebruik
| datum | titel | reden |
|---|---|---|
| 2026-08-10 16:48 / 2026-08-11 06:25 | Optimalisatie printplanning met mutations tabel | nog actief vandaag |
| 2026-08-11 05:18 | Compacte database-opzet voor cutoff times en productielocaties | net gestart, nog geen sql besloten |
| 2026-08-10 15:12 | Production orderlines filteren op lane items en nest items | rubber-duck sessie, nog geen definitieve sql |
| 2026-08-10 14:43 | Schema's selectief samenvoegen (ERD) | `database-erd.md` nog niet in repo gezet |
| 2026-08-10 09:34 | Probo configurators met meerdere materialen | conceptgesprek, loopt nog |

## belangrijkste aandachtspunt
Er zit een terugkerend patroon van **versies die overschreven zijn binnen dezelfde maand** — met name rond nest-planning en timeline-segmenten (29 juli → 1 aug → 2 aug → 9 aug → 10/11 aug). Oogst bij die reeks steeds vanaf de laatste chat terug, niet chronologisch vooruit — anders leg je een tussenversie vast die je een dag later alweer hebt overschreven.
