create table log.hr_data
(
    employee_id          integer,
    department_id        integer,
    department_group_id  integer,
    business_date        date                                              not null,
    shift                text                                              not null,
    start_at             timestamp with time zone,
    end_at               timestamp with time zone,
    source               text                     default 'dyflexis'::text not null,
    source_ref           text,
    ingested_at          timestamp with time zone default now()            not null,
    updated_at           timestamp with time zone default now()            not null,
    constraint uq_hr_data_log
        unique (employee_id, business_date, shift)
);
alter table log.hr_data owner to xfw3;

create table log.hr_shift_planning
(
    shift_planning_id   integer generated always as identity
        constraint pk_shift_planning
            primary key,
    department_group_id integer                                      not null,
    business_date       date                                         not null,
    shift_json          jsonb                    default '{}'::jsonb not null,
    updated_at          timestamp with time zone default now()       not null,
    constraint uq_shift_planning
        unique (department_group_id, business_date)
);
alter table log.hr_shift_planning owner to xfw3;

create index ix_shift_planning_date
    on log.hr_shift_planning (business_date, department_group_id);

-- INCOMPLETE: the source chat text got cut off mid-function. Signature and
-- start of the body are below; the rest (the plans/employees CTEs, the
-- lateral join into log.hr_data for shift_type, the shift_lookup CTE
-- against legacy.lookup, and the final SELECT) needs to be re-pulled from
-- the original chat:
-- https://claude.ai/chat/c5fe2d02-da15-4f94-8cea-671345cbc84f

CREATE OR REPLACE FUNCTION log.get_resource_shift_employees(p_model text, p_until timestamp with time zone)
RETURNS TABLE(
    shift_planning_id   integer,
    shift_type          text,
    content              jsonb,
    department_group_id integer,
    start_at             timestamp with time zone,
    group_name           text,
    employee_id          integer,
    personnel_number     text,
    first_name           text,
    infix                text,
    last_name            text,
    contract_type        text
)
STABLE
LANGUAGE sql
AS $$
WITH matching_resources AS (
    -- Resources that belong to the requested production line model
    SELECT r.resource_uid
    FROM relation.resource r
    JOIN relation.production_line pl ON pl.line_id = r.line_id
    WHERE pl.model = p_model
),
plans AS (
    -- Shift planning ... (cut off here in the source, needs re-pulling)
    SELECT 1  -- placeholder, replace with real body
)
SELECT 1;  -- placeholder, replace with real body
$$;

-- Known design notes from the chat summary (useful when rebuilding the body):
-- - planning comes from log.hr_shift_planning, matched via shift_json->>'resource_uid'
-- - business date filter: direct date comparison using Amsterdam timezone
-- - shift_type per employee resolved via a LATERAL join against log.hr_data
-- - shift_lookup CTE against legacy.lookup is kept, to resolve i18n content blocks
-- - DISTINCT needed to handle possible duplicate employee entries in the planning JSON
-- - primary key column is shift_planning_id (renamed from the old resource_data_log_id)
-- - employees absent from log.hr_data for a given day get null shift_type/content
-- - if the frontend still references the old column name resource_data_log_id, rename back
