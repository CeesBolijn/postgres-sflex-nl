create function relation.get_resource_status(p_resource_id integer) returns TABLE(resource_id integer, status text, error text, task text)
	stable
	language plpgsql
as $$
BEGIN
    RETURN QUERY
    SELECT
        p_resource_id AS resource_id,
        'Online'::text AS status,
        'Geen'::text AS error,
        'Batch 45584 Nest 847569'::text AS task;
END;
$$;

alter function relation.get_resource_status(integer) owner to xfw3;

