create function get_resource_produced(p_resource_uids text[] DEFAULT NULL::text[], p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_until timestamp with time zone DEFAULT now(), p_line_type text DEFAULT NULL::text) returns TABLE(resource_uid text, state jsonb, group_state jsonb, layout_name text, step text, name text, nest_name text, batch_id integer, filename text, page_number integer, batch_name text, data jsonb, start_at timestamp with time zone, offset_seconds numeric, duration_seconds numeric)
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

    select lk.lookup_json into v_lookup_json
      from relation.lookup lk
     where lk.lookup = 'lookup_resource_state'
     limit 1;

    select lk.lookup_json into v_group_state_json
      from relation.lookup lk
     where lk.lookup = 'lookup_resource_group_state'
     limit 1;

    return query
    with state_map as (
        select
            s.value ->> 'code'  as state_code,
            s.value ->> 'group' as group_code,
            s.value             as state_json
        from jsonb_array_elements(v_lookup_json)        as ss(value),
             jsonb_array_elements(ss.value -> 'states') as s(value)
        where s.value ->> 'group' = 'state'
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

alter function get_resource_produced(text[], timestamp with time zone, timestamp with time zone, text) owner to xfw3;

