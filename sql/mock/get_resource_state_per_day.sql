create function get_resource_state_per_day(p_from date DEFAULT '2026-05-01'::date, p_to timestamp with time zone DEFAULT now(), p_tz text DEFAULT 'Europe/Amsterdam'::text) returns TABLE(resource_uid text, resource_name text, line text, day date, state text, time_in_state bigint)
	language plpgsql
as $$
#variable_conflict use_column
begin
    return query
    with intervals as (
        select
            s.resource_uid,
            s.state,
            s.start_at,
            coalesce(
                lead(s.start_at) over (partition by s.resource_uid order by s.start_at),
                p_to
            ) as end_at
        from log.state s
    ),
    clipped as (
        select
            i.resource_uid,
            i.state,
            greatest(i.start_at, p_from::timestamp at time zone p_tz) as seg_start,
            least(i.end_at, p_to)                                     as seg_end
        from intervals i
        where i.end_at   > p_from::timestamp at time zone p_tz
          and i.start_at < p_to
    ),
    per_day as (
        select
            c.resource_uid,
            c.state,
            g::date as day,
            least(c.seg_end, (g + interval '1 day') at time zone p_tz)
              - greatest(c.seg_start, g at time zone p_tz) as duration
        from clipped c
        cross join lateral generate_series(
            date_trunc('day', c.seg_start at time zone p_tz),
            date_trunc('day', c.seg_end   at time zone p_tz),
            interval '1 day'
        ) as g
    )
    select
        pd.resource_uid,
        r.resource_name,
        pl.line,
        pd.day,
        pd.state,
        sum(extract(epoch from pd.duration))::bigint as time_in_state
    from per_day pd
    left join relation.resource         r  on r.resource_uid = pd.resource_uid
    left join relation.production_line  pl on pl.line_id = r.line_id
    group by pd.resource_uid, r.resource_name, pl.line, pd.day, pd.state
    having sum(pd.duration) > interval '0'
    order by pl.line, r.resource_name, pd.resource_uid, pd.day, pd.state;
end;
$$;

alter function get_resource_state_per_day(date, timestamp with time zone, text) owner to xfw3;

