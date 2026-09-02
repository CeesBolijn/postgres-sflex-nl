create or replace function catalog.get_imposition_group_specs(p_imposition_group_id integer) returns jsonb
	stable
	language sql
as $$
    -- The formats a group can be imposed on. One place that knows the alias:
    -- imposition_group_id is material_id for now; when the real groups arrive
    -- this resolves through item_code_paths to the materials of the group and
    -- nothing else changes.
    select coalesce(jsonb_agg(distinct s.value), '[]'::jsonb)
    from mapping.material_production_line m
    cross join lateral jsonb_array_elements(coalesce(m.line_json -> 'specs', '[]'::jsonb)) s
    where m.material_id = p_imposition_group_id   -- alias: group id = material id
      and s.value ? 'width';
$$;

alter function catalog.get_imposition_group_specs(integer) owner to xfw3;
