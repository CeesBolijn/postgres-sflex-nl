# Database erd

Alleen de tabellen die nu al in de repo staan (`sql/action`, `sql/relation`, `sql/log`). Nog niet compleet — aanvullen zodra er meer schema's geoogst zijn uit `inventory.md`.

```mermaid
erDiagram
    action_cutoff_time {
        bigint cutoff_time_uid PK
        text type
        text code
        text rule_path
        smallint weekday
        integer cutoff_seconds
        timestamptz moved_at
        text moved_by
    }

    action_lane_item {
        bigint lane_item_id PK
        bigint lane_id FK
        text step_code
        integer sort_order
    }

    action_lane_item_dependency {
        bigint from_lane_item_id PK_FK
        bigint to_lane_item_id PK_FK
        integer lag_seconds
    }

    action_lane_item_event {
        bigint lane_item_event_id PK
        bigint lane_item_id FK
        text status
        timestamptz moved_at
    }

    action_order_lane_item {
        bigint lane_item_id FK
        bigint order_id
        integer sort_order
    }

    action_nest_lane_item {
        bigint lane_item_id FK
        bigint nest_id
        integer sort_order
    }

    relation_team {
        integer team_id PK
        integer parent_team_id FK
        text description
        integer production_line_id
        integer tenant_id
    }

    action_week_team {
        integer week PK
        integer team_id PK_FK
    }

    log_hr_data {
        integer employee_id
        integer department_id
        integer department_group_id
        date business_date
        text shift
        timestamptz start_at
        timestamptz end_at
    }

    log_hr_shift_planning {
        integer shift_planning_id PK
        integer department_group_id
        date business_date
        jsonb shift_json
    }

    action_lane_item ||--o{ action_lane_item_dependency : "from"
    action_lane_item ||--o{ action_lane_item_dependency : "to"
    action_lane_item ||--o{ action_lane_item_event : "history"
    action_lane_item ||--o{ action_order_lane_item : "order"
    action_lane_item ||--o{ action_nest_lane_item : "nest"
    relation_team ||--o{ relation_team : "parent of"
    relation_team ||--o{ action_week_team : "active in week"
```

## nog niet in dit overzicht
Deze tabellen worden al gebruikt (als foreign key of in een functie) maar staan nog niet als eigen bestand in de repo:
- `action.lane` — `lane_item.lane_id` verwijst ernaar, definitie nog niet geoogst
- `relation.resource`, `relation.equipment`, `relation.production_line` — gebruikt door `get_resource_printer_settings`
- `relation.tenant`, `relation.tenant_domain` — nog niet geoogst, zie `inventory.md`
- `relation.team_contact` — staat als voorstel in commentaar in `sql/relation/team.sql`, nog niet bevestigd

Ook de schema's `mapping`, `catalog`, `core`, `mock` en `legacy` zijn nog niet in dit overzicht opgenomen — daar staat nog niets van in de repo.

## bijwerken
Voeg een tabel toe aan het diagram zodra het bijbehorende sql-bestand in de repo staat.
