create function get_resource_state_aggregate(p_resource_uids text[] DEFAULT NULL::text[], p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_until timestamp with time zone DEFAULT now(), p_line_type text DEFAULT NULL::text) returns TABLE(resource_uid text, step text, state jsonb, duration_seconds numeric, start_at timestamp with time zone, until timestamp with time zone)
	stable
	language plpgsql
as $$
#variable_conflict use_column
declare
    v_running_code    text := 'running';
    v_producing_code  text := 'producing';
    v_data_error_code text := 'data-error';
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

    -- producing / data-error leaf json from the lookup
    state_map as (
        select s.value ->> 'code' as state_code, s.value as state_json
        from relation.lookup                             lk,
             jsonb_array_elements(lk.lookup_json)       as ss(value),
             jsonb_array_elements(ss.value -> 'states') as s(value)
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

        -- data-error = running with no production behind it
        select
            r.resource_uid, st.step, sm.state_json,
            greatest(coalesce(r.envelope_seconds, 0) - coalesce(r.producing_seconds, 0), 0),
            r.start_at, r.until
        from recon     r
        join steps     st on st.resource_uid = r.resource_uid
        join state_map sm on sm.state_code   = v_data_error_code
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

alter function get_resource_state_aggregate(text[], timestamp with time zone, timestamp with time zone, text) owner to xfw3;

