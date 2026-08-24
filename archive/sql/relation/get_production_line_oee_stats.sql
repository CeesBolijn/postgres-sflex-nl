create function relation.get_production_line_oee_stats() returns TABLE(key text, x_value integer, y_value integer)
	language plpgsql
as $$
BEGIN
    RETURN QUERY
    WITH Keys AS (
        SELECT key_name
        FROM (VALUES
            ('oee')
        ) k(key_name)
    ),
    XValues AS (
        SELECT generate_series(1, 10) AS x
    )
    SELECT
        k.key_name::text AS key,
        x.x::integer AS x_value,
        FLOOR(RANDOM() * 100)::int AS y_value
    FROM Keys k
    CROSS JOIN XValues x
    ORDER BY k.key_name, x.x;
END;
$$;

alter function relation.get_production_line_oee_stats() owner to xfw3;

