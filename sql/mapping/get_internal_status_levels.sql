create function mapping.get_internal_status_levels() returns TABLE(level text)
	stable
	language sql
as $$
    SELECT level
    FROM mapping.internal_status
    GROUP BY level
    ORDER BY min(sequence);
$$;

alter function mapping.get_internal_status_levels() owner to xfw3;

