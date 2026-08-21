create function site.test_get_nesting_printfactory(p_nesting_bucket_id character varying, p_bucket_content jsonb DEFAULT NULL::jsonb) returns TABLE(id integer, nesting_bucket_id character varying, document_name text, source_page integer, width numeric, height numeric, position_x numeric, position_y numeric, angle numeric, print_deadline timestamp without time zone, thumbnail_url text)
	language plpgsql
as $$
BEGIN
    RETURN QUERY
    SELECT
        1,
        p_nesting_bucket_id,
        doc ->> 'document_name',
        (doc ->> 'source_page')::integer,
        (doc -> 'size' ->> 'width')::numeric,
        (doc -> 'size' ->> 'height')::numeric,
        (doc -> 'position' ->> 'x')::numeric,
        (doc -> 'position' ->> 'y')::numeric,
        (doc ->> 'angle')::numeric,
        (doc ->> 'print_deadline')::timestamp,
        usf.converted_preview_medium_url
    FROM jsonb_array_elements(COALESCE(p_bucket_content -> 'documents', '[]'::jsonb)) AS doc
    LEFT JOIN mapping.uploader_source_file usf
        ON starts_with(doc ->> 'document_name', regexp_replace(usf.production_filename, '\.[^.]+$', '') || '_');
END;
$$;

alter function site.test_get_nesting_printfactory(varchar, jsonb) owner to xfw3;

