-- ============================================================
-- Migration: the v1 OEE readers move to the flat lookup in log.lookup.
--
-- Four functions, same signatures (plain CREATE OR REPLACE, no drops):
--   log.get_resource_state            flat state_map, alias_of resolves
--                                     starved.operator/blocked.operator;
--                                     group_state = the node itself
--   log.get_resource_state_aggregate  flat state_map; the derived
--                                     residual is 'starved.running'
--                                     (was 'data-error'), same code the
--                                     shift builder writes
--   log.get_resource_produced         flat state_map
--   log.get_resource_plan_batch       flat node resolution
--
-- lookup_resource_group_state and lookup_step_category keep coming
-- from relation.lookup — only lookup_resource_state moved.
-- Still on the old nested relation.lookup (move later):
-- get_resource_state_current, get_resource_plan_impact,
-- action.get_plan_timeline, the mocks.
--
-- Run together with sql/update_data_group_partial.sql (data_groups
-- 19 + 29: state.block.i18n -> state.i18n, color_field ->
-- class_names_field 'state.class_name'). NOTE: class_names_field on
-- donut_chart_config is a new key — the donut widget must read it.
-- ============================================================

BEGIN;

-- ── log.get_resource_state ────────────────────────────────

CREATE OR REPLACE FUNCTION log.get_resource_state(p_resource_uids text[] DEFAULT NULL::text[], p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_until timestamp with time zone DEFAULT now(), p_line_type text DEFAULT NULL::text) returns TABLE(resource_uid text, state jsonb, group_state jsonb, layout_name text, step text, name text, nest_name text, filename text, page_number integer, batch_id integer, batch_name text, data jsonb, start_at timestamp with time zone, offset_seconds numeric, duration_seconds numeric)
	stable
	language plpgsql
as $$
declare
  v_lookup_json jsonb;
  v_day date;
begin
  v_day := coalesce(p_until::date, current_date);
  p_from := coalesce(p_from, (v_day::timestamp + interval '6 hours') at time zone 'Europe/Amsterdam');
  p_until := least(
               coalesce(p_until, (v_day + 1)::timestamp at time zone 'Europe/Amsterdam'),
               now()
             );

  if p_line_type is not null and array_length(p_resource_uids, 1) is null then
    select array_agg(res.resource_uid)
    into p_resource_uids
    from relation.resource res
    join relation.production_line pl on pl.line_id = res.line_id
    where pl.line_type = p_line_type;
  end if;

  -- the flat lookup with counts_as/alias_of lives in log.lookup
  select lk.lookup_json into v_lookup_json
  from log.lookup lk
  where lk.lookup = 'lookup_resource_state'
  limit 1;

  return query
  with
  state_map as (
    -- flat lookup: one node per state. alias_of resolves a source
    -- variant (starved.operator, blocked.operator) to the state it is;
    -- group_state is the resolved node itself, the hierarchy is gone
    select
      s.value ->> 'code'          as state_code,
      coalesce(t.value, s.value)  as state_json,
      coalesce(t.value, s.value)  as group_state_json
    from jsonb_array_elements(v_lookup_json) as s(value)
    left join jsonb_array_elements(v_lookup_json) as t(value)
      on t.value ->> 'code' = s.value ->> 'alias_of'
  ),
  -- last change per resource that starts before the window
  anchor as (
    select r.resource_uid, max(r.start_at) as start_at
    from log.state r
    where r.resource_uid = any(p_resource_uids)
      and r.start_at < p_from
    group by r.resource_uid
  ),
  -- single scan from the anchor up to p_until, with the next change for duration
  windowed as (
    select
      r.resource_uid,
      r.state,
      r.start_at,
      lead(r.start_at) over (partition by r.resource_uid order by r.start_at) as next_at
    from log.state r
    left join anchor a on a.resource_uid = r.resource_uid
    where r.resource_uid = any(p_resource_uids)
      and r.start_at < p_until
      and r.start_at >= coalesce(a.start_at, '-infinity'::timestamptz)
  )
  select
    w.resource_uid,
    sm.state_json,
    sm.group_state_json,
    res.resource_json ->> 'layout_name',
    res.resource_json ->> 'step',
    res.resource_json ->> 'name',
    null::text,      -- nest_name: not on log.state
    null::text,      -- filename: not on log.state
    null::integer,   -- page_number: not on log.state
    null::integer,
    null::text,
    null::jsonb,
    greatest(w.start_at, p_from),
    extract(epoch from (greatest(w.start_at, p_from) - p_from))::numeric,
    extract(epoch from (least(coalesce(w.next_at, p_until), p_until) - greatest(w.start_at, p_from)))::numeric
  from windowed w
  left join relation.resource res on res.resource_uid = w.resource_uid
  left join state_map sm on sm.state_code = w.state
  order by
    res.resource_json ->> 'step' desc,
    res.resource_json ->> 'name',
    greatest(w.start_at, p_from);
end;
$$;

alter function log.get_resource_state(text[], timestamp with time zone, timestamp with time zone, text) owner to xfw3;

-- ── log.get_resource_state_aggregate ──────────────────────

CREATE OR REPLACE FUNCTION log.get_resource_state_aggregate(p_resource_uids text[] DEFAULT NULL::text[], p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_until timestamp with time zone DEFAULT now(), p_line_type text DEFAULT NULL::text) returns TABLE(resource_uid text, step text, state jsonb, duration_seconds numeric, start_at timestamp with time zone, until timestamp with time zone)
	stable
	language plpgsql
as $$
#variable_conflict use_column
declare
    v_running_code         text := 'running';
    v_producing_code       text := 'producing';
    -- running with no production behind it: waiting, same code the
    -- shift builder writes; the lookup aliases it to starved
    v_starved_running_code text := 'starved.running';
    v_from            timestamp with time zone;
begin
    v_from := case
                  when p_from is null
                      then (date_trunc('day', p_until)::timestamp + interval '6 hours')
                           at time zone 'Europe/Amsterdam'
                  else p_from
              end;

    return query
    with
    -- resolved timeline from the fixed function (running, idle, breakdown, setup, ...)
    src as (
        select
            gs.resource_uid,
            gs.step,
            gs.state,
            gs.start_at,
            gs.duration_seconds
        from log.get_resource_state(p_resource_uids, v_from, p_until, p_line_type) gs
        where gs.state is not null
    ),

    steps as (
        select distinct resource_uid, step from src
    ),

    -- producing / starved.running node json from the flat lookup
    state_map as (
        select s.value ->> 'code' as state_code, s.value as state_json
        from log.lookup                        lk,
             jsonb_array_elements(lk.lookup_json) as s(value)
        where lk.lookup = 'lookup_resource_state'
    ),

    -- aggregate per resource + state (everything keeps its resolved state json)
    agg as (
        select
            src.resource_uid,
            src.step,
            src.state,
            sum(src.duration_seconds)::numeric                                  as duration_seconds,
            min(src.start_at)                                                   as start_at,
            max(src.start_at + (src.duration_seconds || ' seconds')::interval)  as until
        from src
        group by src.resource_uid, src.step, src.state
    ),

    -- running envelope per resource
    env as (
        select
            src.resource_uid,
            sum(src.duration_seconds)::numeric                                  as envelope_seconds,
            min(src.start_at)                                                   as start_at,
            max(src.start_at + (src.duration_seconds || ' seconds')::interval)  as until
        from src
        where src.state ->> 'code' = v_running_code
        group by src.resource_uid
    ),

    -- producing time from log.data, scoped to the same resources
    prod as (
        select
            dl.resource_uid,
            sum(dl.production_time_seconds)::numeric as producing_seconds,
            min(dl.start_at)                         as start_at,
            max(dl.start_at)                         as until
        from log.data dl
        where dl.start_at >= v_from
          and dl.start_at <  p_until
          and dl.production_time_seconds > 0
          and dl.resource_uid in (select resource_uid from steps)
        group by dl.resource_uid
    ),

    recon as (
        select
            coalesce(e.resource_uid, p.resource_uid) as resource_uid,
            e.envelope_seconds,
            p.producing_seconds,
            coalesce(p.start_at, e.start_at)         as start_at,
            coalesce(p.until,    e.until)            as until
        from env  e
        full join prod p on p.resource_uid = e.resource_uid
    ),

    combined as (
        -- all resolved states except the running envelope
        select a.resource_uid, a.step, a.state, a.duration_seconds, a.start_at, a.until
        from agg a
        where a.state ->> 'code' <> v_running_code

        union all

        -- producing, timed from log.data
        select
            r.resource_uid, st.step, sm.state_json,
            r.producing_seconds, r.start_at, r.until
        from recon     r
        join steps     st on st.resource_uid = r.resource_uid
        join state_map sm on sm.state_code   = v_producing_code
        where coalesce(r.producing_seconds, 0) > 0

        union all

        -- starved.running = running with no production behind it
        select
            r.resource_uid, st.step, sm.state_json,
            greatest(coalesce(r.envelope_seconds, 0) - coalesce(r.producing_seconds, 0), 0),
            r.start_at, r.until
        from recon     r
        join steps     st on st.resource_uid = r.resource_uid
        join state_map sm on sm.state_code   = v_starved_running_code
        where greatest(coalesce(r.envelope_seconds, 0) - coalesce(r.producing_seconds, 0), 0) > 0
    )

    select
        c.resource_uid,
        c.step,
        c.state,
        c.duration_seconds,
        c.start_at,
        c.until
    from combined c
    order by
        c.resource_uid,
        coalesce((c.state ->> 'order')::integer, 9999),
        c.start_at;
end;
$$;

alter function log.get_resource_state_aggregate(text[], timestamp with time zone, timestamp with time zone, text) owner to xfw3;

-- ── log.get_resource_produced ─────────────────────────────

CREATE OR REPLACE FUNCTION log.get_resource_produced(p_resource_uids text[] DEFAULT NULL::text[], p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_until timestamp with time zone DEFAULT now(), p_line_type text DEFAULT NULL::text) returns TABLE(resource_uid text, state jsonb, group_state jsonb, layout_name text, step text, name text, nest_name text, batch_id integer, filename text, page_number integer, batch_name text, data jsonb, start_at timestamp with time zone, offset_seconds numeric, duration_seconds numeric)
	stable
	language plpgsql
as $$
#variable_conflict use_column
declare
    v_lookup_json      jsonb;
    v_group_state_json jsonb;
    v_day              date;
begin
    v_day   := coalesce(p_until::date, current_date);
    p_from  := coalesce(p_from,  (v_day::timestamp + interval '6 hours') at time zone 'Europe/Amsterdam');
    p_until := least(
               coalesce(p_until, (v_day + 1)::timestamp at time zone 'Europe/Amsterdam'),
               now()
             );

    if p_line_type is not null and array_length(p_resource_uids, 1) is null then
        select array_agg(res.resource_uid)
          into p_resource_uids
          from relation.resource        res
          join relation.production_line pl on pl.line_id = res.line_id
         where pl.line_type = p_line_type;
    end if;

    -- the flat lookup with counts_as/alias_of lives in log.lookup
    select lk.lookup_json into v_lookup_json
      from log.lookup lk
     where lk.lookup = 'lookup_resource_state'
     limit 1;

    select lk.lookup_json into v_group_state_json
      from relation.lookup lk
     where lk.lookup = 'lookup_resource_group_state'
     limit 1;

    return query
    with state_map as (
        -- flat lookup: one node per state
        select
            s.value ->> 'code'  as state_code,
            s.value ->> 'group' as group_code,
            s.value             as state_json
        from jsonb_array_elements(v_lookup_json) as s(value)
    ),
    group_state_map as (
        select
            gs.value ->> 'code' as group_code,
            gs.value            as group_state_json
        from jsonb_array_elements(v_group_state_json) as gs(value)
    ),
    nest_batch as (
        select
            n.nest_name,
            b.batch_id,
            b.batch_name
        from legacy.nest  n
        join legacy.batch b on b.batch_uid = n.batch_uid
    )
    select
        dl.resource_uid,
        sm.state_json,
        gsm.group_state_json,
        res.resource_json ->> 'layout_name',
        res.resource_json ->> 'step',
        res.resource_json ->> 'name',
        dl.nest_name,
        nb.batch_id,
        null::text,          -- filename (niet op log.data)
        dl.page_number,
        nb.batch_name,
        jsonb_build_object(
            'filename',     dl.filename,
            'nest_id',      dl.nest_id,
            'spec_id',      dl.spec_id,
            'amount',       dl.amount,
            'sub_set',      dl.sub_set,
            'step',         dl.step,
            'page_number',  dl.page_number,
            'metrics_json', dl.metrics_json,
            'end_at',       dl.end_at,
            'batch_id',     nb.batch_id
        ),
        dl.start_at,
        extract(epoch from (dl.start_at - p_from))::numeric,
        dl.production_time_seconds::numeric
    from log.data dl
    join relation.resource    res on res.resource_uid = dl.resource_uid
    left join nest_batch      nb  on nb.nest_name     = dl.nest_name
    left join state_map       sm  on sm.state_code    = 'producing'
    left join group_state_map gsm on gsm.group_code   = sm.group_code
    where dl.resource_uid = any(p_resource_uids)
      and dl.start_at >= p_from
      and dl.start_at <  p_until
    order by dl.start_at;
end;
$$;

alter function log.get_resource_produced(text[], timestamp with time zone, timestamp with time zone, text) owner to xfw3;

-- ── log.get_resource_plan_batch ───────────────────────────

CREATE OR REPLACE FUNCTION log.get_resource_plan_batch(p_resource_uids text[] DEFAULT NULL::text[], p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_until timestamp with time zone DEFAULT now(), p_line_type text DEFAULT NULL::text) returns TABLE(resource_uid text, state jsonb, group_state jsonb, layout_name text, step text, name text, nest_name text, filename text, page_number integer, batch_id integer, batch_name text, data jsonb, start_at timestamp with time zone, offset_seconds numeric, duration_seconds numeric)
	stable
	language plpgsql
as $$
DECLARE
    v_lookup_json       jsonb;
    v_group_state_json  jsonb;
    v_day               date;
BEGIN
    v_day := coalesce(p_until::date, current_date);
      -- run to the end of the selected day, but never later than the current time
    p_until := (v_day + 1)::timestamp at time zone 'Europe/Amsterdam';
    p_from := coalesce(p_from, (v_day::timestamp + interval '6 hours') at time zone 'Europe/Amsterdam');

    v_day   := COALESCE(p_until::date, CURRENT_DATE);
    p_until := COALESCE(p_until, ((v_day + 1)::timestamp AT TIME ZONE 'Europe/Amsterdam'));
    p_from  := COALESCE(p_from,  (v_day::timestamp + interval '6 hours') AT TIME ZONE 'Europe/Amsterdam');

    IF p_line_type IS NOT NULL AND array_length(p_resource_uids, 1) IS NULL THEN
        SELECT array_agg(r.resource_uid)
          INTO p_resource_uids
          FROM relation.resource        r
          JOIN relation.production_line pl ON pl.line_id = r.line_id
         WHERE pl.line_type = p_line_type;
    END IF;

    -- the flat lookup with counts_as/alias_of lives in log.lookup
    SELECT lk.lookup_json INTO v_lookup_json
      FROM log.lookup lk
     WHERE lk.lookup = 'lookup_resource_state'
     LIMIT 1;

    SELECT lk.lookup_json INTO v_group_state_json
      FROM relation.lookup lk
     WHERE lk.lookup = 'lookup_resource_group_state'
     LIMIT 1;

    RETURN QUERY
    WITH nests AS (
        SELECT
            obj.action_json ->>'name'        AS batch_name,
            obj.action_json                  AS action_json,
            obj.start_at                     AS start_at,
            obj.action_json ->>'resource_id' AS resource_id,
            (obj.action_json ->>'batch_id')::integer    AS batch_id,
            COALESCE(
                (SELECT jsonb_agg(
                    ba.value
                    || jsonb_build_object(
                        'total_amount',         n.amount::numeric,
                        'internal_status_code', n.nest_json ->>'internal_status_code',
                        'updated_at',           n.nest_json ->>'updated_at'
                    )
                    ORDER BY (ba.value ->>'sequence')::int
                )
                FROM jsonb_array_elements(obj.action_json -> 'data' -> 'batched_amounts') AS ba(value)
                LEFT JOIN legacy.nest n ON n.nest_id = (ba.value ->>'nest_id')::bigint
                ),
                '[]'::jsonb
            ) AS batched_amounts
        FROM action.object obj
    ),
    nest_status AS (
        SELECT
            n.batch_id,
            n.batch_name,
            n.action_json,
            n.start_at,
            n.resource_id,
            n.batched_amounts,
            (SELECT mis.code
             FROM jsonb_array_elements(n.batched_amounts) ba
             JOIN mapping.internal_status mis ON mis.code = (ba->>'internal_status_code')
             ORDER BY mis.sequence
             LIMIT 1)                        AS internal_status_code,
            (SELECT jsonb_agg(jsonb_build_object(
                'internal_status_code', s.status_code,
                'amount',               s.amount,
                'sequence',             s.sequence
            ))
             FROM (
                 SELECT
                     (ba->>'internal_status_code')   AS status_code,
                     SUM((ba->>'total_amount')::int) AS amount,
                     MIN(mis.sequence)               AS sequence
                 FROM jsonb_array_elements(n.batched_amounts) ba
                 JOIN mapping.internal_status mis ON mis.code = (ba->>'internal_status_code')
                 GROUP BY (ba->>'internal_status_code')
             ) s)                            AS nest_status
        FROM nests n
    ),
    resolved_state AS (
        SELECT
            ns.*,
            COALESCE(
                (SELECT s.value
                 FROM jsonb_array_elements(v_lookup_json) AS s(value)
                 WHERE s.value ->>'code' = ns.internal_status_code
                 LIMIT 1),
                (SELECT s.value
                 FROM jsonb_array_elements(v_lookup_json) AS s(value)
                 WHERE s.value ->>'code' = COALESCE(
                     NULLIF(ns.action_json ->>'status', ''),
                     ns.action_json ->>'type',
                     'batch'
                 )
                 LIMIT 1)
            ) AS resolved_state_json
        FROM nest_status ns
    )
    SELECT
        res.resource_uid,
        rs.resolved_state_json,
        (SELECT gs.value
         FROM jsonb_array_elements(v_group_state_json) AS gs(value)
         WHERE gs.value ->>'code' = rs.resolved_state_json ->>'group'
         LIMIT 1),
        res.resource_json ->>'layout_name',
        res.resource_json ->>'step',
        res.resource_json ->>'name',
        NULL::text,
        NULL::text,
        NULL::integer,
        rs.batch_id,
        rs.batch_name,
        jsonb_set(rs.action_json -> 'data', '{batched_amounts}', rs.batched_amounts)
            || jsonb_build_object(
                'internal_status_code', rs.internal_status_code,
                'nest_status',          rs.nest_status
            ),
        rs.start_at,
        EXTRACT(EPOCH FROM (rs.start_at - p_from))::numeric,
        (rs.action_json ->>'duration')::numeric * 60
    FROM resolved_state rs
    JOIN relation.resource res
      ON rs.resource_id = res.resource_json ->>'pv2_id'
    JOIN relation.production_line pl
      ON res.line_id = pl.line_id
    WHERE res.resource_uid = ANY(p_resource_uids)
      --AND rs.action_json -> 'data' ->> 'internal_status_code' <> 'order_announced'
      AND rs.start_at >= p_from
      AND rs.start_at <  p_until
    ORDER BY rs.start_at;
END;
$$;

alter function log.get_resource_plan_batch(text[], timestamp with time zone, timestamp with time zone, text) owner to xfw3;

COMMIT;


-- ============================================================
-- verification
-- ============================================================

-- 1. the timeline resolves every state; expected: no rows
SELECT DISTINCT t.resource_uid, t.start_at
FROM log.get_resource_timeline(NULL, NULL, now(), NULL) t
WHERE t.state IS NULL
LIMIT 10;

-- 2. the donut aggregate: states with hours, starved.running instead
--    of data-error, i18n directly on the node
SELECT a.state ->> 'code'                       AS state,
       a.state -> 'i18n' -> 'nl' ->> 'title'    AS titel,
       a.state ->> 'class_name'                 AS class_name,
       round(sum(a.duration_seconds) / 3600.0, 2) AS hours
FROM log.get_resource_state_aggregate(NULL, NULL, now(), NULL) a
GROUP BY 1, 2, 3
ORDER BY hours DESC;

-- 3. nothing resolves against the old block form anymore; expected: 0
SELECT count(*) AS block_states
FROM log.get_resource_state_aggregate(NULL, NULL, now(), NULL) a
WHERE a.state ? 'block';
