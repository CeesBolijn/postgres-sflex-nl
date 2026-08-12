create function get_resource_timeline(p_resource_uids text[] DEFAULT NULL::text[], p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_until timestamp with time zone DEFAULT now(), p_line_type text DEFAULT NULL::text) returns TABLE(resource_uid text, state jsonb, group_state jsonb, layout_name text, step text, name text, nest_name text, filename text, page_number integer, batch_id integer, batch_name text, data jsonb, start_at timestamp with time zone, offset_seconds numeric, duration_seconds numeric)
	stable
	language plpgsql
as $$
begin
    return query
    select s.resource_uid, s.state, s.group_state, s.layout_name, s.step, s.name,
           s.nest_name, s.filename, s.page_number,
           s.batch_id, s.batch_name, s.data, s.start_at, s.offset_seconds, s.duration_seconds
    from log.get_resource_state(p_resource_uids, p_from, p_until, p_line_type) s
    union all
    select p.resource_uid, p.state, p.group_state, p.layout_name, p.step, p.name,
           p.nest_name, null::text, p.page_number,
           p.batch_id, p.batch_name, p.data, p.start_at, p.offset_seconds, p.duration_seconds
    from log.get_resource_plan_batch(p_resource_uids, p_from, p_until, p_line_type) p
    union all
    select r.resource_uid, r.state, r.group_state, r.layout_name, r.step, r.name,
           r.nest_name, r.filename, r.page_number,
           r.batch_id, r.batch_name, r.data, r.start_at, r.offset_seconds, r.duration_seconds
    from log.get_resource_produced(p_resource_uids, p_from, p_until, p_line_type) r
    union all
    select i.resource_uid, i.state, i.group_state, i.layout_name, i.step, i.name,
           i.nest_name, i.filename, i.page_number,
           i.batch_id, i.batch_name, i.data, i.start_at, i.offset_seconds, i.duration_seconds
    from log.get_resource_plan_impact(p_resource_uids, p_from, p_until, p_line_type) i
    order by
        step,
        name,
        start_at;
end;
$$;

alter function get_resource_timeline(text[], timestamp with time zone, timestamp with time zone, text) owner to xfw3;

