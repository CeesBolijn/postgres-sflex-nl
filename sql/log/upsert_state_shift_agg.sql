create function log.upsert_state_shift_agg(p_date date DEFAULT (CURRENT_DATE - 1)) returns integer
	language plpgsql
as $$
#variable_conflict use_column
declare
  v_from timestamptz := p_date::timestamp at time zone 'Europe/Amsterdam';
  v_until timestamptz := ((p_date + 1)::timestamp at time zone 'Europe/Amsterdam');
  v_count integer;
  v_planned integer;
begin
  drop table if exists tmp_shift, tmp_agg, tmp_produced, tmp_planned;

  create temp table tmp_shift on commit drop as
  select
    sh.ordinality::integer as shift_index,
    (d.date + (sh.value ->> 'start_time')::time) at time zone 'Europe/Amsterdam' as shift_start,
    (d.date + (sh.value ->> 'end_time')::time) at time zone 'Europe/Amsterdam' as shift_end
  from action.dates d
  cross join lateral jsonb_array_elements(d.shift_json) with ordinality as sh(value, ordinality)
  where d.date = p_date
    and d.shift_json is not null;

  create temp table tmp_agg on commit drop as
  with events(resource_uid, state, start_at) as (
    select s.resource_uid, s.state, s.start_at
    from log.state s
    where s.start_at >= v_from and s.start_at < v_until
    union all
    select res.resource_uid, c.state, sh.shift_start
    from relation.resource res
    cross join tmp_shift sh
    cross join lateral (
      select s.state
      from log.state s
      where s.resource_uid = res.resource_uid
        and s.start_at <= sh.shift_start
      order by s.start_at desc
      limit 1
    ) c
  ),
  timeline(resource_uid, state, start_at, end_at) as (
    select
      e.resource_uid,
      e.state,
      e.start_at,
      lead(e.start_at, 1, v_until) over (partition by e.resource_uid order by e.start_at)
    from events e
  )
  select
    sh.shift_index,
    sh.shift_start,
    sh.shift_end,
    t.resource_uid,
    t.state,
    sum(extract(epoch from (least(t.end_at, sh.shift_end) - t.start_at)))::numeric as duration_seconds
  from timeline t
  join tmp_shift sh
    on t.start_at >= sh.shift_start
   and t.start_at < sh.shift_end
  group by sh.shift_index, sh.shift_start, sh.shift_end, t.resource_uid, t.state;

  create temp table tmp_produced on commit drop as
  select sh.shift_index, dl.resource_uid, sum(dl.production_time_seconds)::numeric as produced_seconds
  from log.data dl
  join tmp_shift sh
    on dl.start_at >= sh.shift_start
   and dl.start_at < sh.shift_end
  where dl.production_time_seconds > 0
  group by sh.shift_index, dl.resource_uid;

  -- planning: planned productietijd per shift per resource,
  -- per shift geclipt zodat een item dat over de shiftgrens loopt netjes wordt verdeeld
  create temp table tmp_planned on commit drop as
  with planned(resource_uid, start_at, end_at) as (
    select
      r.resource_uid,
      ao.start_at,
      ao.start_at + (ao.action_json ->> 'duration')::numeric * interval '1 minute'
    from action.object ao
    join relation.resource r
      on r.resource_json ->> 'pv2_id' = ao.action_json ->> 'resource_id'
    where ao.start_at >= v_from and ao.start_at < v_until
      and ao.action_json ->> 'machine_type' = 'printer'
      and (ao.action_json ->> 'type') <> 'interruption'
  )
  select
    sh.shift_index,
    sh.shift_start,
    sh.shift_end,
    p.resource_uid,
    sum(
      extract(epoch from
        least(p.end_at, sh.shift_end) - greatest(p.start_at, sh.shift_start)
      )
    )::numeric as duration_seconds
  from planned p
  join tmp_shift sh
    on p.start_at < sh.shift_end
   and p.end_at   > sh.shift_start
  group by sh.shift_index, sh.shift_start, sh.shift_end, p.resource_uid;

  -- starved = deel van running dat niet produceerde
  insert into tmp_agg (shift_index, shift_start, shift_end, resource_uid, state, duration_seconds)
  select r.shift_index, r.shift_start, r.shift_end, r.resource_uid, 'starved',
         greatest(r.duration_seconds - p.produced_seconds, 0)
  from tmp_agg r
  join tmp_produced p using (shift_index, resource_uid)
  where r.state = 'running';

  -- producing = werkelijke productietijd binnen running; running zelf blijft de volle duur
  insert into tmp_agg (shift_index, shift_start, shift_end, resource_uid, state, duration_seconds)
  select r.shift_index, r.shift_start, r.shift_end, r.resource_uid, 'producing',
         least(p.produced_seconds, r.duration_seconds)
  from tmp_agg r
  join tmp_produced p using (shift_index, resource_uid)
  where r.state = 'running';

  insert into log.state_shift_agg
    (shift_date, shift_index, resource_uid, state, shift_start, shift_end, duration_seconds)
  select p_date, shift_index, resource_uid, state, shift_start, shift_end, sum(duration_seconds)
  from tmp_agg
  group by shift_index, resource_uid, state, shift_start, shift_end
  having sum(duration_seconds) > 0
  on conflict on constraint pk_state_shift_agg
  do update set
    shift_start = excluded.shift_start,
    shift_end = excluded.shift_end,
    duration_seconds = excluded.duration_seconds;

  get diagnostics v_count = row_count;

  -- planned-slice volledig verversen: een plan kan achteraf wijzigen,
  -- zodat een resource die niet meer gepland staat geen stale rij achterlaat
  delete from log.state_shift_agg
  where shift_date = p_date and state = 'planned';

  insert into log.state_shift_agg
    (shift_date, shift_index, resource_uid, state, shift_start, shift_end, duration_seconds)
  select p_date, shift_index, resource_uid, 'planned', shift_start, shift_end, duration_seconds
  from tmp_planned
  where duration_seconds > 0;

  get diagnostics v_planned = row_count;

  return v_count + v_planned;
end;
$$;

alter function log.upsert_state_shift_agg(date) owner to xfw3;

