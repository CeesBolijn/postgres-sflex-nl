-- ============================================================
-- Migration: log.upsert_state_shift_agg rebuilt.
--
-- Five things change:
--
-- 1. delete-then-insert for the whole date. The old version was an
--    upsert with "having sum(duration_seconds) > 0", so a state whose
--    recomputed value dropped to 0 was filtered out instead of
--    updated and its previous row survived. Because log.data lags
--    log.state, the function is re-run for the same date (daily, via
--    site.refresh_derived_data, for current_date - 1 and current_date),
--    and every re-run could leave a ghost behind. Measured before this
--    migration: 1.241 of 4.575 (date, shift, resource) groups in 60
--    days had producing + starved > running, 2.707,7 h too much, and
--    37 groups in 14 days counted exactly double the shift length
--    (two states each filling the whole window).
--
-- 2. the derived residual is written as 'data-error', not 'starved'.
--    'starved' is a state Durst and Zünd log themselves — a period
--    beside running — while the residual is running time with no
--    production behind it. The old code added both under one code, so
--    the value could no longer be summed or split.
--    log.get_resource_state_aggregate already calls this same
--    calculation 'data-error', and the lookup has that code.
--
-- 3. production is spread over [start_at, start_at +
--    production_time_seconds] and clipped per window, instead of
--    booked in full where the row starts. 284 rows in 14 days carried
--    more production time than fitted before the window end: 133,1 h
--    spilled into the wrong shift and partly vanished against the
--    least() cap.
--
-- 4. the derived rows LEFT join the production: running with zero
--    log.data rows (62 of 1.000 shift groups, 515,8 h in 14 days) now
--    becomes data-error in full instead of getting no derived row at
--    all — with counts_as treating running as the envelope, that time
--    would otherwise land in no bucket.
--
-- 5. overnight windows work: shift_end gets the +1 day that
--    log.get_resource_state_shift_totals already applies, and the
--    scan end (v_until) is stretched to the end of the last window,
--    so events and production after midnight still count. Harmless
--    with today's 23:59 pattern, required for the Dyflexis windows
--    (08:00-02:00).
--
-- No DDL: log.state_shift_agg keeps its columns and primary key.
-- Set-based, no temp tables.
--
-- Run order:
--   1. this file (function replace)
--   2. the backfill block at the bottom
--   3. sql/check_state_shift_agg.sql blocks 2 and 6
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION log.upsert_state_shift_agg(p_date date DEFAULT (CURRENT_DATE - 1))
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
#variable_conflict use_column
declare
  v_from  timestamptz := p_date::timestamp at time zone 'Europe/Amsterdam';
  v_until timestamptz := (p_date + 1)::timestamp at time zone 'Europe/Amsterdam';
  v_count integer;
begin
  -- scan until the end of the last window: an overnight window
  -- (end_time <= start_time, +1 day) runs past midnight, so events and
  -- production after 00:00 still belong to this date's windows.
  -- greatest() ignores the null that max() returns when the date has
  -- no shift_json, so v_until then simply stays at the day end
  select greatest(v_until, max(
             (p_date + (sh.value ->> 'end_time')::time
                     + case when (sh.value ->> 'end_time')::time
                                 <= (sh.value ->> 'start_time')::time
                            then interval '1 day' else interval '0' end)
                 at time zone 'Europe/Amsterdam'))
    into v_until
  from action.dates d
  cross join lateral jsonb_array_elements(d.shift_json) as sh(value)
  where d.date = p_date
    and d.shift_json is not null;

  -- the whole date is rebuilt, so a state that no longer applies
  -- disappears instead of lingering next to its replacement
  delete from log.state_shift_agg where shift_date = p_date;

  with
  -- ---------------------------------------------------------------
  -- SWAP POINT: the windows this date is bucketed into.
  -- Today: action.dates.shift_json — one definition for every
  -- resource. That column is already marked for removal (see
  -- sql/migration_dates_tenants_day_off.sql section 3); a per-resource
  -- source (relation.shift_planning / relation.shift_registered_hours)
  -- replaces this CTE and nothing else in the function.
  -- ---------------------------------------------------------------
  window_def as (
      select sh.ordinality::integer as shift_index,
             (p_date + (sh.value ->> 'start_time')::time)
                 at time zone 'Europe/Amsterdam' as shift_start,
             (p_date + (sh.value ->> 'end_time')::time
                     + case when (sh.value ->> 'end_time')::time
                                 <= (sh.value ->> 'start_time')::time
                            then interval '1 day' else interval '0' end)
                 at time zone 'Europe/Amsterdam' as shift_end
      from action.dates d
      cross join lateral jsonb_array_elements(d.shift_json)
                         with ordinality as sh(value, ordinality)
      where d.date = p_date
        and d.shift_json is not null
  ),
  events as (
      select s.resource_uid, s.state, s.start_at
      from log.state s
      where s.start_at >= v_from
        and s.start_at <  v_until

      union all

      -- the state each resource was in when the window opened, so a
      -- window with no events of its own is still covered
      select res.resource_uid, c.state, w.shift_start
      from relation.resource res
      cross join window_def w
      cross join lateral (
          select s.state
          from log.state s
          where s.resource_uid = res.resource_uid
            and s.start_at <= w.shift_start
          order by s.start_at desc
          limit 1
      ) c
  ),
  timeline as (
      select e.resource_uid,
             e.state,
             e.start_at,
             lead(e.start_at, 1, v_until)
                 over (partition by e.resource_uid order by e.start_at) as end_at
      from events e
  ),
  -- everything log.state itself reports, clipped to its window
  logged as (
      select w.shift_index,
             w.shift_start,
             w.shift_end,
             t.resource_uid,
             t.state,
             sum(extract(epoch from (least(t.end_at, w.shift_end) - t.start_at)))::numeric
                 as duration_seconds
      from timeline t
      join window_def w
        on t.start_at >= w.shift_start
       and t.start_at <  w.shift_end
      group by w.shift_index, w.shift_start, w.shift_end, t.resource_uid, t.state
  ),
  -- measured production time inside the same windows. The production is
  -- spread over [start_at, start_at + production_time_seconds] and clipped
  -- per window: booking the full amount at start_at (the old behaviour)
  -- spilled 133 h in 14 days into the wrong shift whenever a job crossed
  -- the boundary, and that excess then vanished against the least() cap.
  -- end_at is not used: 2.172 of 44.595 rows have production_time_seconds
  -- beyond their wall time.
  produced as (
      select w.shift_index,
             dl.resource_uid,
             sum(extract(epoch from (
                 least(dl.start_at + dl.production_time_seconds * interval '1 second',
                       w.shift_end)
                 - greatest(dl.start_at, w.shift_start)
             )))::numeric as produced_seconds
      from log.data dl
      join window_def w
        on dl.start_at < w.shift_end
       and dl.start_at + dl.production_time_seconds * interval '1 second' > w.shift_start
      where dl.production_time_seconds > 0
      group by w.shift_index, dl.resource_uid
  ),
  -- planning: estimated production time. Printers only, matched on
  -- pv2_id; a plan item that crosses a window boundary is clipped so
  -- each window gets its own share
  plan_items as (
      select r.resource_uid,
             ao.start_at,
             ao.start_at + (ao.action_json ->> 'duration')::numeric * interval '1 minute' as end_at
      from action.object ao
      join relation.resource r
        on r.resource_json ->> 'pv2_id' = ao.action_json ->> 'resource_id'
      where ao.start_at >= v_from
        and ao.start_at <  v_until
        and ao.action_json ->> 'machine_type' = 'printer'
        and (ao.action_json ->> 'type') <> 'interruption'
  ),
  plan_windowed as (
      select w.shift_index,
             w.shift_start,
             w.shift_end,
             p.resource_uid,
             sum(extract(epoch from (
                 least(p.end_at, w.shift_end) - greatest(p.start_at, w.shift_start)
             )))::numeric as duration_seconds
      from plan_items p
      join window_def w
        on p.start_at < w.shift_end
       and p.end_at   > w.shift_start
      group by w.shift_index, w.shift_start, w.shift_end, p.resource_uid
  ),
  all_rows as (
      select shift_index, shift_start, shift_end, resource_uid, state, duration_seconds
      from logged

      union all

      -- producing: the measured part of the running envelope
      select l.shift_index, l.shift_start, l.shift_end, l.resource_uid,
             'producing',
             least(coalesce(p.produced_seconds, 0), l.duration_seconds)
      from logged l
      left join produced p
        on p.shift_index   = l.shift_index
       and p.resource_uid  = l.resource_uid
      where l.state = 'running'

      union all

      -- data-error: running with nothing produced behind it. Same name
      -- log.get_resource_state_aggregate uses for the same calculation,
      -- and deliberately not 'starved', which is a logged state.
      -- LEFT join: running with zero log.data rows (62 of 1.000 shift
      -- groups, 515,8 h in 14 days) must become data-error in full —
      -- an inner join would leave that time in no bucket at all
      select l.shift_index, l.shift_start, l.shift_end, l.resource_uid,
             'data-error',
             greatest(l.duration_seconds - coalesce(p.produced_seconds, 0), 0)
      from logged l
      left join produced p
        on p.shift_index   = l.shift_index
       and p.resource_uid  = l.resource_uid
      where l.state = 'running'

      union all

      select shift_index, shift_start, shift_end, resource_uid, 'planned', duration_seconds
      from plan_windowed
  )
  insert into log.state_shift_agg
      (shift_date, shift_index, resource_uid, state, shift_start, shift_end, duration_seconds)
  select p_date,
         a.shift_index,
         a.resource_uid,
         a.state,
         a.shift_start,
         a.shift_end,
         sum(a.duration_seconds)
  from all_rows a
  group by a.shift_index, a.resource_uid, a.state, a.shift_start, a.shift_end
  having sum(a.duration_seconds) > 0;

  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

ALTER FUNCTION log.upsert_state_shift_agg(date) OWNER TO xfw3;

COMMIT;


-- ============================================================
-- backfill — run separately, after the function is in place.
-- Rebuilds every date the table already covers. log.state_shift_agg
-- starts at 2026-05-01 (the planned slice at 2026-05-15), so the
-- range below is the full history; narrow it if you want to do it in
-- batches. Each date is one delete + one insert.
-- ============================================================

-- how much there is to do, and what it looks like now
SELECT min(shift_date) AS first_date,
       max(shift_date) AS last_date,
       count(DISTINCT shift_date) AS dates,
       count(*) AS rows
FROM log.state_shift_agg;

-- the rebuild itself
SELECT d.date, log.upsert_state_shift_agg(d.date) AS rows_written
FROM action.dates d
WHERE d.date BETWEEN '2026-05-01' AND CURRENT_DATE
ORDER BY d.date;


-- ============================================================
-- verification — expected: no rows from 1 and 2, no rows from 3
-- ============================================================

-- 1. producing + data-error must equal running exactly
WITH x AS (
    SELECT shift_date, shift_index, resource_uid,
           sum(duration_seconds) FILTER (WHERE state = 'running')    AS running,
           sum(duration_seconds) FILTER (WHERE state = 'producing')  AS producing,
           sum(duration_seconds) FILTER (WHERE state = 'data-error') AS data_error
    FROM log.state_shift_agg
    GROUP BY 1, 2, 3
)
SELECT * FROM x
WHERE running IS NOT NULL
  AND abs(coalesce(producing, 0) + coalesce(data_error, 0) - running) > 1;

-- 2. the logged states must never exceed the window
SELECT shift_date, shift_index, resource_uid,
       round(sum(duration_seconds) FILTER (
                 WHERE state NOT IN ('producing', 'data-error', 'planned')
             ) / 3600.0, 2) AS logged_hours,
       round(extract(epoch FROM (max(shift_end) - min(shift_start))) / 3600.0, 2) AS window_hours
FROM log.state_shift_agg
GROUP BY 1, 2, 3
HAVING sum(duration_seconds) FILTER (
           WHERE state NOT IN ('producing', 'data-error', 'planned')
       ) > extract(epoch FROM (max(shift_end) - min(shift_start))) + 2;

-- 3. no 'starved' row may be left that is not a logged state
SELECT a.shift_date, a.shift_index, a.resource_uid,
       round(a.duration_seconds / 3600.0, 2) AS starved_hours
FROM log.state_shift_agg a
WHERE a.state = 'starved'
  AND NOT EXISTS (
      SELECT 1 FROM log.state s
      WHERE s.resource_uid = a.resource_uid
        AND s.state IN ('starved', 'starved.operator')
        AND s.start_at >= a.shift_start
        AND s.start_at <  a.shift_end
  );
