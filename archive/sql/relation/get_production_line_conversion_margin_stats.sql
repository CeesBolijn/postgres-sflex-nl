create function relation.get_production_line_conversion_margin_stats() returns TABLE(x_value integer, y1 integer, y2 integer, y3 integer)
	language plpgsql
as $$
BEGIN
    RETURN QUERY
    SELECT
        t.x_value,
        t.y1,
        t.y2,
        t.y3
    FROM (
        SELECT
            v.x AS x_value,
            FLOOR(RANDOM() * 20)::int + 1 AS y1,
            FLOOR(RANDOM() * 20)::int + 1 AS y2,
            FLOOR(RANDOM() * 20)::int + 1 AS y3
        FROM (VALUES
            (1),
            (2),
            (3),
            (4)
        ) v(x)
    ) t;
END;
$$;

alter function relation.get_production_line_conversion_margin_stats() owner to xfw3;

