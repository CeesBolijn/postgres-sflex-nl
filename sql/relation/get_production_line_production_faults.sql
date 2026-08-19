create function get_production_line_production_faults() returns TABLE(error_count integer, stops integer)
	stable
	language plpgsql
as $$
BEGIN
    RETURN QUERY
    SELECT
        36 AS error_count,
        22 AS stops;
END;
$$;

alter function get_production_line_production_faults() owner to xfw3;

