create function mapping.get_status_bar_rework(p_line_id integer) returns jsonb
	stable
	language plpgsql
as $$
BEGIN
    RETURN (
        WITH rw AS (
            SELECT
                COUNT(*) FILTER (WHERE ir.rework_incident_date::date = CURRENT_DATE)::integer AS today,
                COUNT(*) FILTER (WHERE ir.rework_incident_date >= (CURRENT_DATE - INTERVAL '7 days'))::integer AS week
            FROM mapping.internal_rework ir
            WHERE ir.deleted_at IS NULL
              AND ir.production_line_id = p_line_id
        )
        SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
                'code', grp->>'code',
                'i18n', grp->'block'->'i18n',
                'value', CASE grp->>'period'
                    WHEN 'today' THEN rw.today
                    WHEN 'week' THEN rw.week
                END,
                'color', evaluate_conditional_value(
                    grp->'conditional'->'values',
                    grp->'conditional'->'formula',
                    jsonb_build_object('value', CASE grp->>'period'
                        WHEN 'today' THEN rw.today
                        WHEN 'week' THEN rw.week
                    END)
                )
            ) ORDER BY (grp->>'order')::integer
        ), '[]'::jsonb)
        FROM legacy.lookup rl,
             jsonb_array_elements(rl.lookup_json) AS grp
        CROSS JOIN rw
        WHERE rl.lookup = 'lookup_rework'
    );
END;
$$;

alter function mapping.get_status_bar_rework(integer) owner to xfw3;

