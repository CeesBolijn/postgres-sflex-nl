create function relation.get_production_line_status_time() returns TABLE(key text, value integer)
	language plpgsql
as $$
BEGIN
    RETURN QUERY
    SELECT
        k.key_name::text AS key,
        FLOOR(RANDOM() * 100)::int + 1 AS value
    FROM (VALUES
        ('produceren'),
        ('stop'),
        ('inactief'),
        ('storing'),
        ('instellen'),
        ('onderhoud')
    ) k(key_name);
END;
$$;

alter function relation.get_production_line_status_time() owner to xfw3;

