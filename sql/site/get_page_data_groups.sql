create function get_page_data_groups(p_page_id integer) returns jsonb
	language plpgsql
as $$
DECLARE
    v_data_groups TEXT;
BEGIN
    WITH data_groups AS (
        SELECT
            b.block_id,
            col_data->'param_json'->>'data_group' AS data_group
        FROM site.page_block pb
        INNER JOIN site.block b ON pb.block_id = b.block_id
        CROSS JOIN LATERAL jsonb_array_elements(
            COALESCE(b.block_json->'cols', '[]'::jsonb)
        ) AS cols_data
        CROSS JOIN LATERAL jsonb_array_elements(
            COALESCE(cols_data->'col', '[]'::jsonb)
        ) AS col_data
        WHERE pb.page_id = p_page_id
          AND col_data->'param_json'->>'data_group' IS NOT NULL
    )
    SELECT json_agg(
        json_build_object(
            'data_group', dg.data_group || ':' || dgs.block_id::text,
            'data_group_json', dg.data_group_json
        )
    )
    INTO v_data_groups
    FROM site.data_group dg
    INNER JOIN data_groups dgs ON dg.data_group = dgs.data_group;

    RETURN v_data_groups;
END;
$$;

alter function get_page_data_groups(integer) owner to xfw3;

