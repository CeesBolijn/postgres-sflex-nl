create function noop_function() returns TABLE(dummy integer)
	language plpgsql
as $$
BEGIN
    RETURN QUERY SELECT 1;
END;
$$;

alter function noop_function() owner to xfw3;

