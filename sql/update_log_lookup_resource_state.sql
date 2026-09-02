-- ============================================================
-- Update: log.lookup / lookup_resource_state — the simplified, flat
-- form, used ONLY by the OEE read (log.get_resource_state_shift_totals)
-- for now. relation.lookup keeps the old nested form untouched, so
-- every other reader keeps running; they move over later.
--
-- Source of truth: json/lookup/log/lookup_resource_state.json
-- (this script is generated from that file — edit the values THERE,
-- then regenerate; do not edit the JSON below by hand).
--
-- Structure: one flat array, 31 nodes, no hierarchy. Per node: code,
-- i18n (directly on the node, no block wrapper), group, order,
-- class_name, and where applicable counts_as and alias_of. color is
-- gone — class_name carries the styling.
--
-- counts_as has exactly four values, nothing else:
--   producing  producing, setup
--   breakdown  breakdown, maintenance, interruption
--   offline    offline, installation, missingdata
--   planned    planned
-- A state without counts_as (idle, starved(.operator, .running),
-- blocked, ...) sits inside production_hours without being summed
-- anywhere: it is the not-producing loss. running has no counts_as
-- either — it is the envelope of producing + starved.running and
-- would double count.
--
-- order: every group='plan' code (the whole plan lane, maintenance and
-- breaks included) sorts below every machine state, so the timeline
-- shows the plan row above the state row.

BEGIN;

INSERT INTO log.lookup (lookup, lookup_json)
VALUES ('lookup_resource_state', $json$
[
  {
    "code": "not_released",
    "i18n": {
      "de": {
        "title": "Nicht freigegeben"
      },
      "en": {
        "title": "Not released"
      },
      "es": {
        "title": "No liberado"
      },
      "fr": {
        "title": "Non libéré"
      },
      "nl": {
        "title": "Niet vrijgegeven"
      },
      "uk": {
        "title": "Не випущено"
      }
    },
    "group": "plan",
    "order": 10,
    "class_name": "plan-not-released"
  },
  {
    "code": "nesting",
    "i18n": {
      "de": {
        "title": "Verschachtelung"
      },
      "en": {
        "title": "Nesting"
      },
      "es": {
        "title": "Anidando"
      },
      "fr": {
        "title": "Imbrication"
      },
      "nl": {
        "title": "Nesten"
      },
      "uk": {
        "title": "Вкладання"
      }
    },
    "group": "plan",
    "order": 20,
    "class_name": "plan-nesting"
  },
  {
    "code": "nested",
    "i18n": {
      "de": {
        "title": "Verschachtelt"
      },
      "en": {
        "title": "Nested"
      },
      "es": {
        "title": "Anidado"
      },
      "fr": {
        "title": "Imbriqué"
      },
      "nl": {
        "title": "Genest"
      },
      "uk": {
        "title": "Вкладено"
      }
    },
    "group": "plan",
    "order": 30,
    "class_name": "plan-nested"
  },
  {
    "code": "ripping",
    "i18n": {
      "de": {
        "title": "Verarbeitet"
      },
      "en": {
        "title": "Ripped"
      },
      "es": {
        "title": "Procesado"
      },
      "fr": {
        "title": "Traité"
      },
      "nl": {
        "title": "Geript"
      },
      "uk": {
        "title": "Оброблено"
      }
    },
    "group": "plan",
    "order": 40,
    "class_name": "plan-ripping"
  },
  {
    "code": "ripped",
    "i18n": {
      "de": {
        "title": "Verarbeitet"
      },
      "en": {
        "title": "Ripped"
      },
      "es": {
        "title": "Procesado"
      },
      "fr": {
        "title": "Traité"
      },
      "nl": {
        "title": "Geript"
      },
      "uk": {
        "title": "Оброблено"
      }
    },
    "group": "plan",
    "order": 50,
    "class_name": "plan-ripped"
  },
  {
    "code": "cut",
    "i18n": {
      "de": {
        "title": "Geschnitten"
      },
      "en": {
        "title": "Cut"
      },
      "es": {
        "title": "Cortado"
      },
      "fr": {
        "title": "Découpé"
      },
      "nl": {
        "title": "Gesneden"
      },
      "uk": {
        "title": "Розрізано"
      }
    },
    "group": "plan",
    "order": 60,
    "class_name": "plan-cut"
  },
  {
    "code": "printed",
    "i18n": {
      "de": {
        "title": "Gedruckt"
      },
      "en": {
        "title": "Printed"
      },
      "es": {
        "title": "Impreso"
      },
      "fr": {
        "title": "Imprimé"
      },
      "nl": {
        "title": "Geprint"
      },
      "uk": {
        "title": "Надруковано"
      }
    },
    "group": "plan",
    "order": 70,
    "class_name": "plan-printed"
  },
  {
    "code": "laminated",
    "i18n": {
      "de": {
        "title": "Laminiert"
      },
      "en": {
        "title": "Laminated"
      },
      "es": {
        "title": "Laminado"
      },
      "fr": {
        "title": "Laminé"
      },
      "nl": {
        "title": "Gelamineerd"
      },
      "uk": {
        "title": "Ламіновано"
      }
    },
    "group": "plan",
    "order": 80,
    "class_name": "plan-laminated"
  },
  {
    "code": "batch-reserved",
    "i18n": {
      "de": {
        "title": "Stapel reserviert"
      },
      "en": {
        "title": "Batch reserved"
      },
      "es": {
        "title": "Lote reservado"
      },
      "fr": {
        "title": "Lot réservé"
      },
      "nl": {
        "title": "Batch gereserveerd"
      },
      "uk": {
        "title": "Партію зарезервовано"
      }
    },
    "group": "plan",
    "order": 90,
    "class_name": "plan-batch-reserved"
  },
  {
    "code": "batch-initiated",
    "i18n": {
      "de": {
        "title": "Stapel initiiert"
      },
      "en": {
        "title": "Batch initiated"
      },
      "es": {
        "title": "Lote iniciado"
      },
      "fr": {
        "title": "Lot initié"
      },
      "nl": {
        "title": "Batch geïnitieerd"
      },
      "uk": {
        "title": "Партію ініційовано"
      }
    },
    "group": "plan",
    "order": 100,
    "class_name": "plan-batch-initiated"
  },
  {
    "code": "batch",
    "i18n": {
      "de": {
        "title": "Stapel"
      },
      "en": {
        "title": "Batch"
      },
      "es": {
        "title": "Lote"
      },
      "fr": {
        "title": "Lot"
      },
      "nl": {
        "title": "Batch"
      },
      "uk": {
        "title": "Партія"
      }
    },
    "group": "plan",
    "order": 110,
    "class_name": "plan-batch"
  },
  {
    "code": "impact",
    "i18n": {
      "de": {
        "title": "Produktionsauswirkung"
      },
      "en": {
        "title": "Production impact"
      },
      "es": {
        "title": "Impacto de producción"
      },
      "fr": {
        "title": "Impact de production"
      },
      "nl": {
        "title": "Productie impact"
      },
      "uk": {
        "title": "Вплив на виробництво"
      }
    },
    "group": "plan",
    "order": 120,
    "class_name": "plan-impact"
  },
  {
    "code": "planned",
    "i18n": {
      "de": {
        "title": "Geplant"
      },
      "en": {
        "title": "Planned"
      },
      "es": {
        "title": "Planificado"
      },
      "fr": {
        "title": "Planifié"
      },
      "nl": {
        "title": "Gepland"
      },
      "uk": {
        "title": "Заплановано"
      }
    },
    "group": "state",
    "order": 130,
    "class_name": "plan",
    "counts_as": "planned"
  },
  {
    "code": "breaks",
    "i18n": {
      "de": {
        "title": "Pause"
      },
      "en": {
        "title": "Break"
      },
      "es": {
        "title": "Pausa"
      },
      "fr": {
        "title": "Pause"
      },
      "nl": {
        "title": "Break"
      },
      "uk": {
        "title": "Перерва"
      }
    },
    "group": "plan",
    "order": 140,
    "class_name": "plan-breaks"
  },
  {
    "code": "changeovertime",
    "i18n": {
      "de": {
        "title": "Umrüstzeit"
      },
      "en": {
        "title": "Changeover time"
      },
      "es": {
        "title": "Tiempo de cambio"
      },
      "fr": {
        "title": "Temps de changement"
      },
      "nl": {
        "title": "Changeover time"
      },
      "uk": {
        "title": "Час переналагодження"
      }
    },
    "group": "plan",
    "order": 150,
    "class_name": "plan-changeovertime"
  },
  {
    "code": "ticket",
    "i18n": {
      "de": {
        "title": "Ticket"
      },
      "en": {
        "title": "Ticket"
      },
      "es": {
        "title": "Ticket"
      },
      "fr": {
        "title": "Ticket"
      },
      "nl": {
        "title": "Ticket"
      },
      "uk": {
        "title": "Заявка"
      }
    },
    "group": "plan",
    "order": 160,
    "class_name": "plan-ticket"
  },
  {
    "code": "maintenance",
    "i18n": {
      "de": {
        "title": "Wartung"
      },
      "en": {
        "title": "Maintenance"
      },
      "es": {
        "title": "Mantenimiento"
      },
      "fr": {
        "title": "Maintenance"
      },
      "nl": {
        "title": "Maintenance"
      },
      "uk": {
        "title": "Обслуговування"
      }
    },
    "group": "plan",
    "order": 170,
    "class_name": "plan-maintenance",
    "counts_as": "breakdown"
  },
  {
    "code": "interruption",
    "i18n": {
      "de": {
        "title": "Unterbrechung"
      },
      "en": {
        "title": "Interruption"
      },
      "es": {
        "title": "Interrupción"
      },
      "fr": {
        "title": "Interruption"
      },
      "nl": {
        "title": "Onderbreking"
      },
      "uk": {
        "title": "Перерва у роботі"
      }
    },
    "group": "plan",
    "order": 180,
    "class_name": "plan-interruption",
    "counts_as": "breakdown"
  },
  {
    "code": "producing",
    "i18n": {
      "de": {
        "title": "Produziert"
      },
      "en": {
        "title": "Producing"
      },
      "es": {
        "title": "Produciendo"
      },
      "fr": {
        "title": "En production"
      },
      "nl": {
        "title": "Producing"
      },
      "uk": {
        "title": "Виробництво"
      }
    },
    "group": "state",
    "order": 190,
    "class_name": "state-producing",
    "counts_as": "producing"
  },
  {
    "code": "setup",
    "i18n": {
      "de": {
        "title": "Rüsten"
      },
      "en": {
        "title": "Setup"
      },
      "es": {
        "title": "Configuración"
      },
      "fr": {
        "title": "Configuration"
      },
      "nl": {
        "title": "Setup"
      },
      "uk": {
        "title": "Налаштування"
      }
    },
    "group": "state",
    "order": 200,
    "class_name": "state-setup",
    "counts_as": "producing"
  },
  {
    "code": "running",
    "i18n": {
      "de": {
        "title": "Läuft"
      },
      "en": {
        "title": "Running"
      },
      "es": {
        "title": "En marcha"
      },
      "fr": {
        "title": "En marche"
      },
      "nl": {
        "title": "Running"
      },
      "uk": {
        "title": "В роботі"
      }
    },
    "group": "state",
    "order": 210,
    "class_name": "state-running"
  },
  {
    "code": "idle",
    "i18n": {
      "de": {
        "title": "Leerlauf"
      },
      "en": {
        "title": "Idle"
      },
      "es": {
        "title": "Inactivo"
      },
      "fr": {
        "title": "Inactif"
      },
      "nl": {
        "title": "Idle"
      },
      "uk": {
        "title": "Неактивний"
      }
    },
    "group": "state",
    "order": 220,
    "class_name": "state-idle"
  },
  {
    "code": "starved",
    "i18n": {
      "de": {
        "title": "Materialmangel"
      },
      "en": {
        "title": "Starved"
      },
      "es": {
        "title": "Sin material"
      },
      "fr": {
        "title": "Sous-alimenté"
      },
      "nl": {
        "title": "Starved"
      },
      "uk": {
        "title": "Голодування"
      }
    },
    "group": "state",
    "order": 230,
    "class_name": "state-starved"
  },
  {
    "code": "starved.operator",
    "i18n": {
      "de": {
        "title": "Materialmangel"
      },
      "en": {
        "title": "Starved"
      },
      "es": {
        "title": "Sin material"
      },
      "fr": {
        "title": "Sous-alimenté"
      },
      "nl": {
        "title": "Starved"
      },
      "uk": {
        "title": "Голодування"
      }
    },
    "group": "state",
    "order": 240,
    "class_name": "state-starved",
    "alias_of": "starved"
  },
  {
    "code": "blocked",
    "i18n": {
      "de": {
        "title": "Blockiert"
      },
      "en": {
        "title": "Blocked"
      },
      "es": {
        "title": "Bloqueado"
      },
      "fr": {
        "title": "Bloqué"
      },
      "nl": {
        "title": "Blocked"
      },
      "uk": {
        "title": "Заблоковано"
      }
    },
    "group": "state",
    "order": 250,
    "class_name": "state-blocked"
  },
  {
    "code": "blocked.operator",
    "i18n": {
      "de": {
        "title": "Blockiert"
      },
      "en": {
        "title": "Blocked"
      },
      "es": {
        "title": "Bloqueado"
      },
      "fr": {
        "title": "Bloqué"
      },
      "nl": {
        "title": "Blocked"
      },
      "uk": {
        "title": "Заблоковано"
      }
    },
    "group": "state",
    "order": 260,
    "class_name": "state-blocked",
    "alias_of": "blocked"
  },
  {
    "code": "starved.running",
    "i18n": {
      "de": {
        "title": "Materialmangel"
      },
      "en": {
        "title": "Starved"
      },
      "es": {
        "title": "Sin material"
      },
      "fr": {
        "title": "Sous-alimenté"
      },
      "nl": {
        "title": "Starved"
      },
      "uk": {
        "title": "Голодування"
      }
    },
    "group": "state",
    "order": 270,
    "class_name": "state-starved",
    "alias_of": "starved"
  },
  {
    "code": "breakdown",
    "i18n": {
      "de": {
        "title": "Störung"
      },
      "en": {
        "title": "Breakdown"
      },
      "es": {
        "title": "Avería"
      },
      "fr": {
        "title": "Panne"
      },
      "nl": {
        "title": "Breakdown"
      },
      "uk": {
        "title": "Поломка"
      }
    },
    "group": "state",
    "order": 280,
    "class_name": "state-breakdown",
    "counts_as": "breakdown"
  },
  {
    "code": "missingdata",
    "i18n": {
      "de": {
        "title": "Fehlende Daten"
      },
      "en": {
        "title": "Missing data"
      },
      "es": {
        "title": "Datos faltantes"
      },
      "fr": {
        "title": "Données manquantes"
      },
      "nl": {
        "title": "Missing data"
      },
      "uk": {
        "title": "Відсутні дані"
      }
    },
    "group": "state",
    "order": 290,
    "class_name": "state-missingdata",
    "counts_as": "offline"
  },
  {
    "code": "offline",
    "i18n": {
      "de": {
        "title": "Offline"
      },
      "en": {
        "title": "Offline"
      },
      "es": {
        "title": "Sin conexión"
      },
      "fr": {
        "title": "Hors ligne"
      },
      "nl": {
        "title": "Offline"
      },
      "uk": {
        "title": "Офлайн"
      }
    },
    "group": "state",
    "order": 300,
    "class_name": "state-offline",
    "counts_as": "offline"
  },
  {
    "code": "installation",
    "i18n": {
      "de": {
        "title": "Installation"
      },
      "en": {
        "title": "Installation"
      },
      "es": {
        "title": "Instalación"
      },
      "fr": {
        "title": "Installation"
      },
      "nl": {
        "title": "Installation"
      },
      "uk": {
        "title": "Інсталяція"
      }
    },
    "group": "state",
    "order": 310,
    "class_name": "state-installation",
    "counts_as": "offline"
  }
]
$json$::jsonb)
ON CONFLICT (lookup) DO UPDATE
SET lookup_json = EXCLUDED.lookup_json;

COMMIT;


-- ============================================================
-- verification
-- ============================================================

-- 1. flat and clean: 31 nodes, none nested, no old-form keys, no
--    counts_as outside the four buckets; expected: 31 | 0 | 0 | 0
SELECT jsonb_array_length(l.lookup_json)                                       AS nodes,
       count(*) FILTER (WHERE g.value ? 'states')                              AS nested,
       count(*) FILTER (WHERE NOT (g.value ? 'i18n') OR g.value ? 'block'
                           OR g.value ? 'color')                              AS old_form,
       count(*) FILTER (WHERE g.value ? 'counts_as'
                          AND g.value ->> 'counts_as' NOT IN
                              ('producing', 'breakdown', 'offline', 'planned')) AS bad_counts_as
FROM log.lookup l,
     jsonb_array_elements(l.lookup_json) AS g(value)
WHERE l.lookup = 'lookup_resource_state'
GROUP BY l.lookup_json;

-- 2. bucket overview, to check the counts_as choices in one go
SELECT coalesce(g.value ->> 'counts_as', '(none: loss inside production_hours)') AS counts_as,
       string_agg(g.value ->> 'code', ', ' ORDER BY (g.value ->> 'order')::int)  AS states
FROM log.lookup l,
     jsonb_array_elements(l.lookup_json) AS g(value)
WHERE l.lookup = 'lookup_resource_state'
GROUP BY 1
ORDER BY 1;

-- 3. states in the data without a node in the new lookup; expected: no rows
WITH lookup_codes AS (
    SELECT g.value ->> 'code' AS code
    FROM log.lookup l,
         jsonb_array_elements(l.lookup_json) AS g(value)
    WHERE l.lookup = 'lookup_resource_state'
),
used AS (
    SELECT DISTINCT state FROM log.state
    UNION
    SELECT DISTINCT state FROM log.state_shift_agg
)
SELECT u.state
FROM used u
LEFT JOIN lookup_codes lc ON lc.code = u.state
WHERE lc.code IS NULL
ORDER BY u.state;

-- 4. the old lookup in relation.lookup is untouched; expected: 4
--    top-level nodes, still nested
SELECT jsonb_array_length(l.lookup_json) AS top_level_nodes,
       l.lookup_json::text LIKE '%"states"%' AS still_nested
FROM relation.lookup l
WHERE l.lookup = 'lookup_resource_state';
