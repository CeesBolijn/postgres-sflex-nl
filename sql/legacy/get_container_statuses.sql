create function legacy.get_container_statuses(p_container_id integer DEFAULT NULL::integer) returns TABLE(lijnen jsonb)
	language plpgsql
as $$
BEGIN
    RETURN QUERY SELECT (
    (
        SELECT jsonb_agg(
            jsonb_build_object(
                'name', line.assigned_line,
                'color', line.color,
                'containers',
            (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'containerId', sub.container_id,
                    'name', sub.container_name,
                    'xPos', sub.x_pos,
                    'yPos', sub.y_pos,
                    'status', CASE sub.status
                    WHEN FALSE THEN 'leeg'
                    ELSE 'vol' END
                )
            )
            FROM legacy.containers AS sub
            WHERE sub.assigned_line = line.assigned_line
            AND (p_container_id IS NULL OR sub.container_id = p_container_id))
            )
        )
        FROM (SELECT DISTINCT assigned_line, color
        FROM legacy.containers
        WHERE (p_container_id IS NULL OR container_id = p_container_id)) AS line
    )
) AS lijnen;
END;
$$;

alter function legacy.get_container_statuses(integer) owner to xfw3;

