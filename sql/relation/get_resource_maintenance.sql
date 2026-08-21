create function relation.get_resource_maintenance() returns TABLE(notifications text, planned timestamp with time zone, last timestamp with time zone)
	stable
	language plpgsql
as $$
BEGIN
    RETURN QUERY
    SELECT
        'Yup'::text AS notifications,
        NOW() AS planned,
        NOW() AS last;
END;
$$;

alter function relation.get_resource_maintenance() owner to xfw3;

