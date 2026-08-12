# Probo repo

Eén bron van waarheid voor alle sql-functies en json-structuren. Geen versies meer los in chats.

## structuur
```
sql/<schema>/<functie_naam>.sql   -- één functie per bestand
json/<naam>.json                  -- json-structuren
docs/inventory.md                 -- checklist van wat nog geoogst moet worden
CLAUDE.md                         -- vaste conventies, wordt automatisch meegelezen
```

## werkwijze
1. Elke sql-functie of json-structuur die je bespreekt, komt hier terecht — niet los in een chat laten hangen.
2. Bij een wijziging: bestand aanpassen en committen. Geen "_v2" of "_final" bestandsnamen, git houdt de historie bij.
3. Nieuwe chat of Claude Code sessie start met deze repo als context.
4. Zodra een onderwerp uit `docs/inventory.md` hier staat: vinkje zetten, oude chat verwijderen.
