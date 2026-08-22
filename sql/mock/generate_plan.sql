create or replace function mock.generate_plan(p_date date, p_step text, p_line_type text) returns TABLE(plan_id bigint, lane_id bigint, material_resource_plan_id bigint)
	language sql
as $$
    WITH pattern AS (
        SELECT DISTINCT ON (m.sort_order)
               m.material_resource_plan_id, m.sort_order, m.material_id,
               m.start_offset_in_seconds, m.is_pinned
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
        -- tenant_ids: the tenants that run this line_type
        INSERT INTO action.plan (plan_date, steps, type, line_type, tenant_ids)
        SELECT p_date, array[p_step], 'material-resource-plan', p_line_type,
               (SELECT array_agg(DISTINCT pl.tenant_id ORDER BY pl.tenant_id)
                       FILTER (WHERE pl.tenant_id IS NOT NULL)
                FROM relation.production_line pl
                WHERE pl.line_type = p_line_type)
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
    ),
    -- one slot per lane, stamped from the pattern row: the planned moment
    -- the client moves, pins and copies. The pattern stays the template.
    new_lane_item AS (
        INSERT INTO action.lane_item
            (lane_id, sort_order, start_offset_in_seconds, is_pinned,
             no_split, level, source, source_ref)
        SELECT nl.lane_id, p.sort_order, p.start_offset_in_seconds,
               coalesce(p.is_pinned, false), true, 0,
               'material-plan', p.material_resource_plan_id || ':' || p_date
        FROM numbered_lane nl
        JOIN numbered_pattern p USING (rn)
        RETURNING lane_item_id, lane_id
    ),
    -- the material of the slot, on the item
    new_material_lane_item AS (
        INSERT INTO action.material_lane_item (material_id, lane_item_id)
        SELECT p.material_id, nli.lane_item_id
        FROM new_lane_item nli
        JOIN numbered_lane nl ON nl.lane_id = nli.lane_id
        JOIN numbered_pattern p USING (rn)
        WHERE p.material_id IS NOT NULL
        RETURNING lane_item_id
    )
    INSERT INTO mock.material_resource_plan_lane (lane_id, material_resource_plan_id)
    SELECT npl.lane_id, p.material_resource_plan_id
    FROM new_plan_lane npl
    JOIN numbered_pattern p ON p.sort_order = npl.sort_order
    RETURNING (SELECT plan_id FROM new_plan), lane_id, material_resource_plan_id;
$$;

alter function mock.generate_plan(date, text, text) owner to xfw3;
