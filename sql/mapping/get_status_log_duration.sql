create function get_status_log_duration(p_production_orderline_id integer) returns TABLE(status_log_id integer, production_orderline_id integer, previous_internal_status_code character varying, update_internal_status_code character varying, next_internal_status_code character varying, updated_at timestamp without time zone, duration_seconds numeric)
	language plpgsql
as $$
#variable_conflict use_column
BEGIN
    RETURN QUERY
    SELECT
        sl.status_log_id,
        sl.object_id,
        isp.code AS previous_internal_status_code,
        isu.code AS update_internal_status_code,
        isn.code AS next_internal_status_code,
        sl.updated_at,
        EXTRACT(EPOCH FROM (LEAD(sl.updated_at) OVER (PARTITION BY sl.object_id ORDER BY sl.updated_at) - sl.updated_at)) AS duration_seconds
    FROM mapping.status_log sl
    LEFT JOIN mapping.internal_status isp
        ON isp.internal_status_id = sl.previous_internal_status_id
       AND isp.domain_id = sl.domain_id
    LEFT JOIN mapping.internal_status isu
        ON isu.internal_status_id = sl.update_internal_status_id
       AND isu.domain_id = sl.domain_id
    LEFT JOIN mapping.internal_status isn
        ON isn.internal_status_id = sl.next_internal_status_id
       AND isn.domain_id = sl.domain_id
    WHERE sl.object_id = p_production_orderline_id
      AND sl.line_json ->> 'object_level' = 'production_orderline'
    ORDER BY sl.updated_at desc;
END;
$$;

alter function get_status_log_duration(integer) owner to xfw3;

