create function legacy.get_info(p_resource_uids text[] DEFAULT NULL::text[], p_model text DEFAULT NULL::text, p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_until timestamp with time zone DEFAULT NULL::timestamp with time zone) returns TABLE(resource_uids text, model text, "from" timestamp with time zone, until timestamp with time zone, description text)
	language plpgsql
as $$
BEGIN
    RETURN QUERY
    SELECT
        array_to_string(p_resource_uids, ','),
        p_model,
        p_from,
        p_until,
        'legacy.get_info worked'::text;
END;
$$;

alter function legacy.get_info(text[], text, timestamp with time zone, timestamp with time zone) owner to xfw3;

