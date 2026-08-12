create function crud_resource_state(p_param_json jsonb, p_no_results boolean DEFAULT false) returns TABLE(param_id integer, track_by integer, crud text, resource_uid text, status text, nest_name text, job_name text, page_number integer, start_at timestamp with time zone, resource_status_json jsonb)
	language plpgsql
as $$
DECLARE
    r record;
BEGIN
    -- Verwerk inkomende 'create' records chronologisch per resource_uid
    FOR r IN
        SELECT
            (t.data->>'resource_uid')                       AS resource_uid,
            (t.data->>'state')                              AS state,
            (t.data->>'nest_name')                          AS nest_name,
            (t.data->>'job_name')                           AS job_name,
            COALESCE((t.data->>'page_number')::integer, 1)  AS page_number,
            (t.data->>'fetched_at')::timestamptz            AS start_at,
            t.data->'resource_state_json'                   AS resource_state_json
        FROM jsonb_to_recordset(p_param_json)
             AS t(crud text, data jsonb)
        WHERE t.crud                  = 'create'
          AND t.data->>'resource_uid' IS NOT NULL
          AND t.data->>'state'        IS NOT NULL
        ORDER BY (t.data->>'fetched_at')::timestamptz ASC
    LOOP
        -- db_latest = meest recente bestaande rij vóór dit nieuwe tijdstip
        INSERT INTO legacy.resource_state_log (
            resource_uid, state, nest_name, job_name,
            page_number, start_at, resource_state_json
        )
        SELECT
            r.resource_uid,
            r.state,
            r.nest_name,
            r.job_name,
            r.page_number,
            r.start_at,
            r.resource_state_json
        WHERE
            r.state IS DISTINCT FROM (
                SELECT rsl.state
                FROM   legacy.resource_state_log rsl
                WHERE  rsl.resource_uid = r.resource_uid
                  AND  rsl.start_at     <= r.start_at
                ORDER BY rsl.start_at DESC, rsl.resource_state_log_id DESC
                LIMIT 1
            );
    END LOOP;

    IF NOT p_no_results THEN
        RETURN QUERY
        SELECT
            row_number() OVER (
                ORDER BY (t.data->>'fetched_at')::timestamptz
            )::integer,
            COALESCE((t.track_by)::integer, 0),
            t.crud,
            t.data->>'resource_uid',
            t.data->>'state',
            t.data->>'nest_name',
            t.data->>'job_name',
            COALESCE((t.data->>'page_number')::integer, 1),
            (t.data->>'fetched_at')::timestamptz,
            t.data->'resource_state_json'
        FROM jsonb_to_recordset(p_param_json)
             AS t(track_by integer, crud text, data jsonb)
        WHERE t.data->>'resource_uid' IS NOT NULL
          AND t.data->>'state'        IS NOT NULL
        ORDER BY (t.data->>'fetched_at')::timestamptz;
    END IF;
END;
$$;

alter function crud_resource_state(jsonb, boolean) owner to xfw3;

