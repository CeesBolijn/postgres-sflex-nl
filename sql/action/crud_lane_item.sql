create function action.crud_lane_item(p_param_json jsonb, p_no_results boolean DEFAULT false) returns TABLE(param_id integer, track_by integer, crud text, lane_item_id bigint, lane_id bigint)
	language plpgsql
as $$
#variable_conflict use_column
begin
    -- The client mutations of the planning boards, on lane_item level
    -- (docs/nest-planning-lane-items.md phase 3). One payload row is one of:
    --   update — move/pin: writes sort_order, offset, duration, is_pinned
    --   create — an extra moment: on a lane (lane_id), as a copy of an item
    --            (lane_item_id: same lane, same group link), or on a fresh
    --            lane of a plan (plan_id only — the print agenda copy)
    --   delete — removes the moment and its nest links (group link cascades)
    create temp table li_param on commit drop as
    select row_number() over ()::integer as param_id,
           coalesce(te.track_by, 0)      as track_by,
           te.crud, te.lane_item_id, te.lane_id, te.plan_id,
           te.start_offset_in_seconds, te.sort_order, te.is_pinned,
           te.duration_in_seconds, te.imposition_group_id
    from jsonb_array_elements(p_param_json) as t(element)
    cross join lateral jsonb_to_record(t.element) as te(
        track_by integer, crud text, lane_item_id bigint, lane_id bigint,
        plan_id bigint, start_offset_in_seconds integer, sort_order numeric,
        is_pinned boolean, duration_in_seconds integer, imposition_group_id integer);

    -- move / pin: only the provided fields change
    update action.lane_item li
    set sort_order              = coalesce(p.sort_order, li.sort_order),
        start_offset_in_seconds = coalesce(p.start_offset_in_seconds, li.start_offset_in_seconds),
        duration_in_seconds     = coalesce(p.duration_in_seconds, li.duration_in_seconds),
        is_pinned               = coalesce(p.is_pinned, li.is_pinned)
    from li_param p
    where p.crud = 'update' and li.lane_item_id = p.lane_item_id;

    -- a print-agenda copy gets its own lane first, hung in plan_lane;
    -- created ids pair back to the payload by rank (insert in param order)
    create temp table li_new_lane on commit drop as
    with need as (
        select p.param_id, pl.plan_date, p.plan_id, p.sort_order,
               row_number() over (order by p.param_id) as rn
        from li_param p
        join action.plan pl on pl.plan_id = p.plan_id
        where p.crud = 'create' and p.lane_id is null and p.lane_item_id is null
    ),
    ins as (
        insert into action.lane (lane_date)
        select n.plan_date from need n order by n.rn
        returning lane_id
    ),
    ranked as (
        select i.lane_id, row_number() over (order by i.lane_id) as rn from ins i
    )
    select n.param_id, r.lane_id, n.plan_id, n.sort_order
    from need n join ranked r using (rn);

    insert into action.plan_lane (plan_id, lane_id, sort_order)
    select nl.plan_id, nl.lane_id,
           coalesce(nl.sort_order,
                    (select coalesce(max(pl2.sort_order), 0) + 1000
                     from action.plan_lane pl2 where pl2.plan_id = nl.plan_id))
    from li_new_lane nl;

    -- the new moments themselves
    create temp table li_created on commit drop as
    with target as (
        select p.param_id, p.track_by,
               coalesce(p.lane_id, src.lane_id, nl.lane_id)                       as lane_id,
               p.sort_order                                                       as sort_order,
               coalesce(p.start_offset_in_seconds, src.start_offset_in_seconds)   as start_offset_in_seconds,
               coalesce(p.duration_in_seconds, src.duration_in_seconds, 0)        as duration_in_seconds,
               coalesce(p.is_pinned, src.is_pinned, false)                        as is_pinned,
               -- a copy takes the group of its source along
               coalesce(p.imposition_group_id, igli.imposition_group_id)          as imposition_group_id
        from li_param p
        left join action.lane_item src on src.lane_item_id = p.lane_item_id
        left join action.imposition_group_lane_item igli on igli.lane_item_id = p.lane_item_id
        left join li_new_lane nl on nl.param_id = p.param_id
        where p.crud = 'create'
    ),
    valid as (
        select t.*, row_number() over (order by t.param_id) as rn
        from target t
        where t.lane_id is not null
    ),
    ins as (
        insert into action.lane_item
            (lane_id, sort_order, start_offset_in_seconds, duration_in_seconds,
             is_pinned, no_split, level, source)
        select v.lane_id,
               -- no rank from the client: append behind the lane, spread so a
               -- batch never collides on the unique (lane_id, sort_order)
               coalesce(v.sort_order,
                        (select coalesce(max(li2.sort_order), 0)
                         from action.lane_item li2 where li2.lane_id = v.lane_id)
                        + 1000 * v.rn),
               v.start_offset_in_seconds, v.duration_in_seconds,
               v.is_pinned, true, 0, 'planner'
        from valid v
        order by v.rn
        returning lane_item_id, lane_id
    ),
    ranked as (
        select i.lane_item_id, i.lane_id, row_number() over (order by i.lane_item_id) as rn from ins i
    )
    select v.param_id, v.track_by, r.lane_item_id, r.lane_id, v.imposition_group_id
    from valid v
    join ranked r using (rn);

    insert into action.imposition_group_lane_item (imposition_group_id, lane_item_id)
    select c.imposition_group_id, c.lane_item_id
    from li_created c
    where c.imposition_group_id is not null
    on conflict do nothing;

    -- delete: the moment, its nest links; the group link cascades
    delete from action.nest_lane_item nli
    using li_param p
    where p.crud = 'delete' and nli.lane_item_id = p.lane_item_id;

    delete from action.lane_item li
    using li_param p
    where p.crud = 'delete' and li.lane_item_id = p.lane_item_id;

    if not p_no_results then
        return query
        select p.param_id, p.track_by, p.crud,
               coalesce(c.lane_item_id, p.lane_item_id),
               coalesce(c.lane_id, p.lane_id)
        from li_param p
        left join li_created c on c.param_id = p.param_id
        order by p.param_id;
    end if;
end;
$$;

alter function action.crud_lane_item(jsonb, boolean) owner to xfw3;
