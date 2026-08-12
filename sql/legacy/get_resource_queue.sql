create function get_resource_queue(p_resource_uids text[] DEFAULT NULL::text[], p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_until timestamp with time zone DEFAULT NULL::timestamp with time zone) returns TABLE(nest_name text, amount integer, width numeric, height numeric, state jsonb, nested_date timestamp with time zone)
	stable
	language plpgsql
as $$
DECLARE
    v_day date;
BEGIN
    v_day := COALESCE(p_until::date, CURRENT_DATE);

    IF p_until IS NULL THEN
        p_until := (v_day + 1)::timestamp;
    END IF;

    IF p_from IS NULL THEN
        p_from := v_day::timestamp + interval '6 hours';
    END IF;

    RETURN QUERY
    SELECT
        n.nest_name,
        n.amount,
        n.width,
        n.height,
        (n.nest_json->'state'),
        (n.nest_json->>'nested_date')::timestamptz
    FROM legacy.nest n
    WHERE n.nest_name IN (
        SELECT DISTINCT rdl.nest_name
        FROM legacy.resource_data_log rdl
        WHERE rdl.resource_uid = (
                SELECT r.resource_json ->>'for_resource_uid'
                FROM relation.resource r
                WHERE r.resource_uid = p_resource_uids[1]
                LIMIT 1
            )
          AND rdl.start_at >= p_from
          AND rdl.start_at <  p_until
          AND rdl.nest_name IS NOT NULL
    );
END;
$$;

alter function get_resource_queue(text[], timestamp with time zone, timestamp with time zone) owner to xfw3;

