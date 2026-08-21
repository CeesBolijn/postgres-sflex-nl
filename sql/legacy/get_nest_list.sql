create function legacy.get_nest_list(p_production_line_id integer DEFAULT NULL::integer, p_resource_uids text[] DEFAULT NULL::text[], p_internal_status text[] DEFAULT ARRAY['printed'::text], p_require_thumbnail boolean DEFAULT true) returns TABLE(nest_name text, nest_id bigint, nested_at timestamp with time zone, printed_at timestamp with time zone, nest_json jsonb, sqm numeric, material_name text)
	stable
	language sql
as $$
    SELECT DISTINCT ON (n.nest_name)
        n.nest_name,
        n.nest_id,
        n.nested_at,
        rdl.start_at AS printed_at,
        n.nest_json,
        (n.nest_json->>'amount')::numeric
            * (n.nest_json->>'width')::numeric
            * (n.nest_json->>'height')::numeric / 10000 AS sqm,
        mpl.line_json->>'name' AS material_name
    FROM legacy.nest n
    JOIN legacy.batch b
      ON b.batch_uid = n.batch_uid
     AND (p_production_line_id IS NULL
          OR (b.batch_json->>'production_line_id')::int = p_production_line_id)
    LEFT JOIN mapping.material_production_line mpl
      ON mpl.material_id = (n.nest_json->>'material_id')::int
    LEFT JOIN LATERAL (
        SELECT rdl.start_at
        FROM legacy.resource_data_log rdl
        WHERE rdl.nest_name = n.nest_name
          AND (p_resource_uids IS NULL OR rdl.resource_uid = ANY (p_resource_uids))
        ORDER BY rdl.start_at DESC NULLS LAST
        LIMIT 1
    ) rdl ON true
    WHERE n.nest_json->>'internal_status_code' = ANY (p_internal_status)
      AND (p_resource_uids IS NULL OR rdl.start_at IS NOT NULL)
      AND (NOT p_require_thumbnail
        OR NULLIF(n.nest_json->>'job_thumbnail', '') IS NOT NULL)
    ORDER BY n.nest_name, n.nested_at DESC NULLS LAST;
$$;

alter function legacy.get_nest_list(integer, text[], text[], boolean) owner to xfw3;

