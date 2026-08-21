create function site.noop_function() returns TABLE(dummy integer)
	language plpgsql
as $$
BEGIN
    RETURN QUERY SELECT 1;
END;
$$;

alter function site.noop_function() owner to xfw3;

