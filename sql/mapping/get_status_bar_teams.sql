create function get_status_bar_teams(p_model text, p_until timestamp with time zone) returns jsonb
	stable
	language plpgsql
as $$
BEGIN
    RETURN (
        WITH shift AS (
            SELECT group_name, COUNT(employee_id)::integer AS amount, start_at
            FROM legacy.get_resource_shift_employees(p_model, COALESCE(p_until, now()))
            GROUP BY shift_type, start_at, group_name
        ),
        latest AS (
            SELECT DISTINCT ON (group_name) group_name, amount
            FROM shift
            ORDER BY group_name, start_at DESC
        ),
        teams AS (
            SELECT
                grp->>'code'  AS code,
                grp->'i18n'   AS i18n,
                grp->>'order' AS order_key,
                COALESCE(SUM(l.amount), 0)::integer AS value
            FROM relation.lookup rl
            CROSS JOIN jsonb_array_elements(rl.lookup_json) AS grp
            LEFT JOIN latest l
                ON grp->'codes' @> to_jsonb(public.to_kebab(l.group_name))
            WHERE rl.lookup = 'lookup_teams'
            GROUP BY grp->>'code', grp->'i18n', grp->>'order'
        )
        SELECT COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'code', code,
                    'i18n', i18n,
                    'value', value
                ) ORDER BY order_key
            ),
            '[]'::jsonb
        )
        FROM teams
    );
END;
$$;

alter function get_status_bar_teams(text, timestamp with time zone) owner to xfw3;

