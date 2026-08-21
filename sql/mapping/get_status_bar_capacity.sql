create function mapping.get_status_bar_capacity(p_model text, p_until timestamp with time zone, p_line_id integer, p_steps jsonb) returns jsonb
	stable
	language plpgsql
as $$
BEGIN
    RETURN (
        SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
                'code', s->>'step',
                'i18n', s->'i18n',
                'value', COALESCE(sa.available, 0)
            )
        ), '[]'::jsonb)
        FROM jsonb_array_elements(p_steps) AS s
        LEFT JOIN LATERAL (
            SELECT ROUND(SUM(rsc.capacity_left), 1) AS available
            FROM log.get_resource_state_current(COALESCE(p_until, now()), p_model) rsc
            JOIN relation.resource r ON r.resource_uid = rsc.resource_uid
            WHERE rsc.production_line_id = p_line_id
              AND r.step = s->>'step'
        ) sa ON true
    );
END;
$$;

alter function mapping.get_status_bar_capacity(text, timestamp with time zone, integer, jsonb) owner to xfw3;

