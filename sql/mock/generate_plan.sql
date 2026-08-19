create or replace function mock.generate_plan(p_date date, p_step text, p_line_type text) returns TABLE(plan_id bigint, lane_id bigint, material_resource_plan_id bigint)
	language sql
as $$
    WITH pattern AS (
        SELECT DISTINCT ON (m.sort_order)
               m.material_resource_plan_id, m.sort_order
        FROM mock.material_resource_plan m
        WHERE m.weekday = extract(dow FROM p_date)::smallint + 1
          AND m.step = p_step
          AND m.production_line_id IN (
                SELECT DISTINCT production_line_id
                FROM mock.material_print_schedule
                WHERE line = p_line_type)
        ORDER BY m.sort_order, m.moved_at DESC, m.material_resource_plan_id DESC
    ),
    new_plan AS (
        INSERT INTO action.plan (plan_date, steps, type, line_type)
        VALUES (p_date, array[p_step], 'material-resource-plan', p_line_type)
        RETURNING plan_id
    ),
    new_lane AS (
        INSERT INTO action.lane (plan_id, sort_order)
        SELECT np.plan_id, p.sort_order
        FROM pattern p
        CROSS JOIN new_plan np
        RETURNING lane_id, plan_id, sort_order
    )
    INSERT INTO mock.material_resource_plan_lane (lane_id, material_resource_plan_id)
    SELECT nl.lane_id, p.material_resource_plan_id
    FROM new_lane nl
    JOIN pattern p ON p.sort_order = nl.sort_order
    RETURNING (SELECT plan_id FROM new_plan), lane_id, material_resource_plan_id;
$$;

alter function mock.generate_plan(date, text, text) owner to xfw3;

