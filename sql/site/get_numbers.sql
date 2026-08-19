create function get_numbers(p_numbers integer[]) returns TABLE(number integer)
	language plpgsql
as $$
BEGIN
    RETURN QUERY SELECT unnest(p_numbers);
END;
$$;

alter function get_numbers(integer[]) owner to xfw3;

