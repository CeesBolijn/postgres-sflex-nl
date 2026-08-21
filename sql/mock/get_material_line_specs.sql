create function mock.get_material_line_specs(p_material_id integer) returns TABLE(width numeric, height numeric, sides integer)
	stable
	language plpgsql
as $$
#variable_conflict use_column
BEGIN
    RETURN QUERY
    SELECT
        (mpl.line_json -> 'specs' -> 0 ->> 'width')::numeric,
        (mpl.line_json -> 'specs' -> 0 ->> 'height')::numeric,
        COALESCE((mpl.line_json -> 'specs' -> 0 ->> 'sides')::integer, 1)
    FROM mapping.material_production_line mpl
    WHERE mpl.material_id = p_material_id
    ORDER BY mpl.production_line_id
    LIMIT 1;
END;
$$;

alter function mock.get_material_line_specs(integer) owner to xfw3;

