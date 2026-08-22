create function legacy.get_nest_detail(p_nest_id bigint DEFAULT NULL::bigint, p_batch_id integer DEFAULT NULL::integer, p_nest_ids bigint[] DEFAULT NULL::bigint[]) returns TABLE(batch_id integer, nest_id bigint, nest_name text, nest_json jsonb, nested_at timestamp with time zone, updated_at timestamp with time zone, start_at timestamp with time zone)
	language plpgsql
as $$
    #variable_conflict use_column
DECLARE
    v_batch_id integer;
    v_nest_id bigint;
BEGIN
    -- a set of nests resolves through its first nest; a single nest through itself
    v_nest_id  := COALESCE(p_nest_id, p_nest_ids[1]);
    v_batch_id := p_batch_id;

    IF v_batch_id IS NULL THEN
        SELECT n.batch_id
        INTO v_batch_id
        FROM legacy.nest n
        WHERE n.nest_id = v_nest_id;
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
    -- batch found: every nest of the batch; no batch: every nest of the
    -- given set, or just the single nest when no set was given
    WHERE (n.batch_id = v_batch_id)
       OR (v_batch_id IS NULL AND p_nest_ids IS NOT NULL AND n.nest_id = ANY (p_nest_ids))
       OR (v_batch_id IS NULL AND p_nest_ids IS NULL AND n.nest_id = v_nest_id)
    ORDER BY rdl.start_at DESC;
END;
$$;

alter function legacy.get_nest_detail(bigint, integer, bigint[]) owner to xfw3;
