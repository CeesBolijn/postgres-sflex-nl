create function legacy.get_nest_buckets(p_nest_ids integer[]) returns TABLE(nest_id integer, bucket_name text, batch_id integer, nested_at timestamp with time zone, nest_name text, amount integer, width numeric, height numeric, material_id integer, material_name text, waste_percentage numeric, commercial_waste_percentage numeric, material_width numeric, material_height numeric, job_thumbnail jsonb)
	stable
	language sql
as $$
    -- #variable_conflict use_column

    SELECT
        nest.nest_id,
        nest.bucket_name,
        nest.batch_id,
        nest.nested_at,
        nest.nest_name,
        nest.amount,
        nest.width,
        nest.height,
        (nest.nest_json->>'material_id')::integer AS material_id,
        mn.material_name,
        (nest.nest_json->>'waste_percentage')::numeric AS waste_percentage,
        (nest.nest_json->>'commercial_waste_percentage')::numeric AS commercial_waste_percentage,
        (nest.nest_json->>'material_width')::numeric AS material_width,
        (nest.nest_json->>'material_height')::numeric AS material_height,
        nest.nest_json->'job_thumbnail' AS job_thumbnail
    FROM legacy.nest
    LEFT JOIN LATERAL (
        SELECT DISTINCT ON (mpl.material_id)
            mpl.line_json ->> 'material_name' AS material_name
        FROM mapping.material_production_line mpl
        WHERE mpl.material_id = (nest.nest_json->>'material_id')::integer
        ORDER BY mpl.material_id
    ) mn ON TRUE
    WHERE nest.nest_id = ANY (p_nest_ids);
$$;

alter function legacy.get_nest_buckets(integer[]) owner to xfw3;

