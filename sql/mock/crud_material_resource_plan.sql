create function crud_material_resource_plan(p_data jsonb, p_cascade boolean DEFAULT true) returns SETOF mock.material_resource_plan
	language sql
as $$
    WITH input AS (
        SELECT (e ->> 'weekday')::smallint                         AS weekday,
                e ->> 'step'                                       AS step,
                e ->> 'resource_uid'                               AS resource_uid,
               (e ->> 'sort_order')::numeric                       AS sort_order,
               (e ->> 'material_id')::integer                      AS material_id,
               coalesce((e ->> 'duration_in_seconds')::integer, 0) AS duration_in_seconds
        FROM jsonb_array_elements(p_data) AS e
    ),
    -- Pre-insert snapshot of the affected lanes, read only when absorbing.
    current_lane AS (
        SELECT DISTINCT ON (p.weekday, p.step, p.resource_uid, p.sort_order)
               p.weekday, p.step, p.resource_uid, p.sort_order,
               p.material_id, p.duration_in_seconds
        FROM mock.material_resource_plan p
        WHERE NOT coalesce(p_cascade, true)
          AND EXISTS (SELECT 1 FROM input i
                      WHERE i.weekday = p.weekday AND i.step = p.step
                        AND i.resource_uid IS NOT DISTINCT FROM p.resource_uid)
        ORDER BY p.weekday, p.step, p.resource_uid, p.sort_order,
                 p.moved_at DESC, p.material_resource_plan_id DESC
    ),
    -- Match every inserted row to its own first following spacer, then total per spacer.
    claim AS (
        SELECT i.weekday, i.step, i.resource_uid, s.sort_order, s.duration_in_seconds,
               sum(i.duration_in_seconds)::integer AS claimed_in_seconds
        FROM input i
        JOIN LATERAL (
            SELECT l.sort_order, l.duration_in_seconds FROM current_lane l
            WHERE l.weekday = i.weekday AND l.step = i.step
              AND l.resource_uid IS NOT DISTINCT FROM i.resource_uid
              AND l.material_id IS NULL AND l.sort_order > i.sort_order
            ORDER BY l.sort_order LIMIT 1
        ) s ON true
        GROUP BY 1, 2, 3, 4, 5
    ),
    absorbed AS (
        INSERT INTO mock.material_resource_plan
            (weekday, step, resource_uid, sort_order, material_id, duration_in_seconds)
        SELECT weekday, step, resource_uid, sort_order, NULL,
               greatest(duration_in_seconds - claimed_in_seconds, 0)
        FROM claim
        RETURNING *
    ),
    inserted AS (
        INSERT INTO mock.material_resource_plan
            (weekday, step, resource_uid, sort_order, material_id, duration_in_seconds)
        SELECT weekday, step, resource_uid, sort_order, material_id, duration_in_seconds
        FROM input
        RETURNING *
    )
    SELECT * FROM inserted UNION ALL SELECT * FROM absorbed;
$$;

alter function crud_material_resource_plan(jsonb, boolean) owner to xfw3;

