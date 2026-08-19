create function get_resource_info(p_resource_id integer) returns TABLE(type text, serial text, resource_id integer, brand text, location text)
	stable
	language plpgsql
as $$
BEGIN
    RETURN QUERY
    SELECT
        r.resource_json->>'cutterType' AS type,
        r.resource_json->>'serialNo' AS serial,
        r.resource_id,
        '-'::text AS brand,
        '-'::text AS location
    FROM relation.resource r
    WHERE r.resource_id = p_resource_id;
END;
$$;

alter function get_resource_info(integer) owner to xfw3;

