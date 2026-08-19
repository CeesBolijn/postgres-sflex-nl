create function mock.generate_production_plan(p_date date, p_step text DEFAULT 'print'::text, p_line_type text DEFAULT 'sheet'::text) returns TABLE(plan_id bigint, lane_id bigint, resource_paths ltree[])
	language sql
as $$
    -- A production plan for one day and one step: one lane per active
    -- resource of that step on the line type, in the order the resources
    -- carry (pv2_order, then name). The lane records the resource path as it
    -- is now (see docs/resource-path.md). Lane items come later, from the
    -- planner (level 0) and the logs (level 1).
    with resource as (
        select r.resource_path,
               row_number() over (order by (r.resource_json ->> 'pv2_order')::numeric nulls last, r.resource_name)::numeric as sort_order
        from relation.resource r
        join relation.production_line pl on pl.line_id = r.line_id
        where r.active
          and r.resource_path is not null
          and r.step = p_step
          and pl.line_type = p_line_type
    ),
    new_plan as (
        insert into action.plan (plan_date, steps, type, line_type)
        values (p_date, array[p_step], 'production-plan', p_line_type)
        returning plan_id
    )
    insert into action.lane (plan_id, sort_order, resource_paths)
    select np.plan_id, rs.sort_order, array[rs.resource_path]
    from resource rs
    cross join new_plan np
    returning plan_id, lane_id, resource_paths;
$$;

alter function mock.generate_production_plan(date, text, text) owner to xfw3;
