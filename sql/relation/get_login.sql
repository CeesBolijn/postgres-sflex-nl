create function relation.get_login() returns TABLE(email text, password text, reset_token text)
	language plpgsql
as $$
BEGIN
RETURN QUERY SELECT '' email, '' password, '' reset_token;
END;
$$;

alter function relation.get_login() owner to xfw3;

