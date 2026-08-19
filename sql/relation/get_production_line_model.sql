create function get_production_line_model() returns TABLE(glb_url text)
	stable
	language plpgsql
as $$
BEGIN
    RETURN QUERY
    SELECT
        'https://f003.backblazeb2.com/file/xfw-storage/probo/3d/Untitled.glb'::text AS glb_url;
END;
$$;

alter function get_production_line_model() owner to xfw3;

