create function legacy.get_nest_detail(p_nest_id bigint DEFAULT NULL::bigint, p_batch_id integer DEFAULT NULL::integer) returns TABLE(batch_id integer, nest_id bigint, nest_name text, nest_json jsonb, nested_at timestamp with time zone, updated_at timestamp with time zone, start_at timestamp with time zone)
	language plpgsql
as $$
    #variable_conflict use_column
DECLARE
    v_batch_id integer;
BEGIN
    v_batch_id := p_batch_id;

    IF v_batch_id IS NULL THEN
        SELECT n.batch_id
        INTO v_batch_id
        FROM legacy.nest n
        WHERE n.nest_id = p_nest_id;
    END IF;

    RETURN QUERY
    SELECT
        n.batch_id,
        n.nest_id,
        n.nest_name,
        n.nest_json,
        n.nested_at,
        n.updated_at,
        rdl.start_at
    FROM legacy.nest n
    LEFT JOIN legacy.resource_data_log rdl
        ON rdl.nest_name = n.nest_name
    WHERE (v_batch_id IS NULL and n.nest_id = p_nest_id) OR (n.batch_id = v_batch_id)
--       AND n.nest_json->'job_thumbnail' IS NOT NULL
--       AND n.nest_json->'job_thumbnail'->>'_error' IS NULL
    ORDER BY rdl.start_at DESC;
END;
$$;

alter function legacy.get_nest_detail(bigint, integer) owner to xfw3;

