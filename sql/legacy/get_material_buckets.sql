create function get_material_buckets(p_production_line_id integer DEFAULT NULL::integer, p_material_id integer DEFAULT NULL::integer) returns TABLE(production_line_id integer, material_id integer, bucket_name text)
	language plpgsql
as $$
#variable_conflict use_column
BEGIN
    RETURN QUERY
    SELECT DISTINCT
        mpl.production_line_id,
        mpl.material_id,
        n.bucket_name
    FROM legacy.nest n
    JOIN mapping.material_production_line mpl
        ON (n.nest_json->>'material_id')::int = mpl.material_id
    WHERE n.bucket_name NOT LIKE '% - 126%'
        AND n.bucket_name NOT LIKE '%.pdf%'
        AND (p_production_line_id IS NULL OR mpl.production_line_id = p_production_line_id)
        AND (p_material_id IS NULL OR mpl.material_id = p_material_id);
END;
$$;

alter function get_material_buckets(integer, integer) owner to xfw3;

