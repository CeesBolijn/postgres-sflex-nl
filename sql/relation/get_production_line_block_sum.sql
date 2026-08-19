create function get_production_line_block_sum() returns TABLE(error_time integer, error_supply integer, error_rejected integer, error_ink integer, error_personell integer)
	stable
	language plpgsql
as $$
BEGIN
    RETURN QUERY
    SELECT
        46 AS error_time,
        46 AS error_supply,
        46 AS error_rejected,
        2 AS error_ink,
        4 AS error_personell;
END;
$$;

alter function get_production_line_block_sum() owner to xfw3;

