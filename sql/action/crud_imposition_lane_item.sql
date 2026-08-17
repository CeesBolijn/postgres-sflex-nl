create function action.crud_imposition_lane_item(p_param_json jsonb, p_no_results boolean DEFAULT false) returns TABLE(imposition_lane_item_id bigint, lane_item_id bigint, imposition_id bigint, moved_at timestamp with time zone)
	language sql
as $$
    -- Write a set for a lane_item. Called on the first step and on a split or
    -- merge; never for steps that keep the same set. All rows of one call
    -- share a moved_at, so the "most recent write per lane_item" rule in
    -- get_lane_item_impositions sees them as one set.
    with inserted as (
        insert into action.imposition_lane_item (lane_item_id, imposition_id)
        select (el ->> 'lane_item_id')::bigint,
               (el ->> 'imposition_id')::bigint
        from jsonb_array_elements(p_param_json) as el
        returning imposition_lane_item_id, lane_item_id, imposition_id, moved_at
    )
    select * from inserted where not p_no_results;
$$;

alter function action.crud_imposition_lane_item(jsonb, boolean) owner to xfw3;
