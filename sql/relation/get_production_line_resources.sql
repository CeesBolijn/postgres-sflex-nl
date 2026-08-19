create function get_production_line_resources() returns TABLE(resource_id integer, color text)
	language plpgsql
as $$
BEGIN
    RETURN QUERY
    SELECT
        r.resource_id,
        CONCAT('#', SUBSTRING(MD5(gen_random_uuid()::text), 1, 6)) AS color
    FROM relation.resource r
    ORDER BY r.resource_id
    LIMIT 15;
END;
$$;

alter function get_production_line_resources() owner to xfw3;

