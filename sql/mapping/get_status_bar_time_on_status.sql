create function get_status_bar_time_on_status(p_model text, p_until timestamp with time zone, p_line_id integer) returns jsonb
	stable
	language plpgsql
as $$
DECLARE
    v_result jsonb;
BEGIN
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'code', lk.code,
            'i18n', lk.i18n,
            'color', lk.color,
            'value', lk.cnt
        )
    ), '[]'::jsonb)
    INTO v_result
    FROM (
        SELECT
            cl.code,
            cl.i18n,
            cl.color,
            COUNT(t.time_on_status_hours)::integer AS cnt
        FROM (
            SELECT
                grp->>'code' AS code,
                grp->'block'->'i18n' AS i18n,
                grp->>'color' AS color,
                (grp->>'min_value')::numeric AS min_value,
                (grp->>'max_value')::numeric AS max_value
            FROM legacy.lookup rl,
                 jsonb_array_elements(rl.lookup_json) AS grp
            WHERE rl.lookup = 'lookup_time_on_status'
        ) cl
        LEFT JOIN mapping.get_time_on_status(p_model, COALESCE(p_until, now()), 1, p_line_id) t
            ON t.time_on_status_hours >= cl.min_value
           AND (cl.max_value IS NULL OR t.time_on_status_hours < cl.max_value)
        GROUP BY cl.code, cl.i18n, cl.color
    ) lk;

    RETURN v_result;
END;
$$;

alter function get_status_bar_time_on_status(text, timestamp with time zone, integer) owner to xfw3;

