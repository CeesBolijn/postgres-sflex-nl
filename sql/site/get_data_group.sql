create function get_data_group(p_data_group text) returns TABLE(data_group_json jsonb)
	stable
	language sql
as $$
    SELECT site.resolve_nav_refs(data_group_json)
    FROM site.data_group
    WHERE data_group = p_data_group;
$$;

alter function get_data_group(text) owner to xfw3;

