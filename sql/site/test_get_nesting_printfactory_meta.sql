create function site.test_get_nesting_printfactory_meta(p_nesting_bucket_id character varying, p_bucket_content jsonb DEFAULT NULL::jsonb) returns TABLE(source text, sheet_width numeric, sheet_height numeric)
	language plpgsql
as $$
BEGIN
    RETURN QUERY
    SELECT
        'printfactory'::text,
        (p_bucket_content -> 'media' ->> 'width')::numeric,
        (p_bucket_content -> 'media' ->> 'length')::numeric;
END;
$$;

alter function site.test_get_nesting_printfactory_meta(varchar, jsonb) owner to xfw3;

