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
    numbered_pattern AS (
        SELECT p.*, row_number() OVER (ORDER BY p.sort_order) AS rn FROM pattern p
    ),
    new_plan AS (
        INSERT INTO action.plan (plan_date, steps, type, line_type)
        VALUES (p_date, array[p_step], 'material-resource-plan', p_line_type)
        RETURNING plan_id
    ),
    -- material lanes: one fresh lane per pattern row, no resource paths
    new_lane AS (
        INSERT INTO action.lane (lane_date)
        SELECT p_date FROM pattern
        RETURNING lane_id
    ),
    numbered_lane AS (
        SELECT nl.lane_id, row_number() OVER (ORDER BY nl.lane_id) AS rn FROM new_lane nl
    ),
    new_plan_lane AS (
        INSERT INTO action.plan_lane (plan_id, lane_id, sort_order)
        SELECT np.plan_id, nl.lane_id, p.sort_order
        FROM numbered_lane nl
        JOIN numbered_pattern p USING (rn)
        CROSS JOIN new_plan np
        RETURNING plan_id, lane_id, sort_order
    )
    INSERT INTO mock.material_resource_plan_lane (lane_id, material_resource_plan_id)
    SELECT npl.lane_id, p.material_resource_plan_id
    FROM new_plan_lane npl
    JOIN numbered_pattern p ON p.sort_order = npl.sort_order
    RETURNING (SELECT plan_id FROM new_plan), lane_id, material_resource_plan_id;
$$;

alter function mock.generate_plan(date, text, text) owner to xfw3;

