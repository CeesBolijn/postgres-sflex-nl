create function crud_status_log(p_param_json jsonb, p_no_results boolean DEFAULT false) returns TABLE(status_log_id integer, domain_id integer, object_id integer, line_json jsonb)
	language plpgsql
as $$
DECLARE
    v_last_status_log_id text;
BEGIN

    WITH incoming AS (
        SELECT DISTINCT ON (d_id, o_id, u_at)
            d_id, log_id, o_id,
            previous_internal_status_id,
            update_internal_status_id,
            next_internal_status_id,
            el, u_at
        FROM (
            SELECT
                (el->>'domain_id')::integer                   AS d_id,
                (el->>'log_id')::text                         AS log_id,
                (el->>'object_id')::integer                   AS o_id,
                (el->>'previous_internal_status_id')::integer AS previous_internal_status_id,
                (el->>'update_internal_status_id')::integer   AS update_internal_status_id,
                (el->>'next_internal_status_id')::integer     AS next_internal_status_id,
                el,
                (el->>'updated_at')::timestamp                AS u_at
            FROM jsonb_array_elements(p_param_json) AS el
        ) sub
        ORDER BY d_id, o_id, u_at, log_id DESC
    ),

    latest AS (
        SELECT DISTINCT ON (sl.domain_id, sl.object_id)
            sl.domain_id,
            sl.object_id,
            sl.previous_internal_status_id,
            sl.update_internal_status_id,
            sl.next_internal_status_id
        FROM mapping.status_log sl
        WHERE (sl.domain_id, sl.object_id) IN (
            SELECT d_id, o_id FROM incoming
        )
        ORDER BY sl.domain_id, sl.object_id, sl.updated_at DESC
    ),

    filtered AS (
        SELECT i.*
        FROM incoming i
        LEFT JOIN latest l
            ON  l.domain_id  = i.d_id
            AND l.object_id  = i.o_id
        WHERE l.domain_id IS NULL
           OR i.previous_internal_status_id IS DISTINCT FROM l.previous_internal_status_id
           OR i.update_internal_status_id   IS DISTINCT FROM l.update_internal_status_id
           OR i.next_internal_status_id     IS DISTINCT FROM l.next_internal_status_id
    )

    INSERT INTO mapping.status_log (
        domain_id, log_id, object_id,
        previous_internal_status_id, update_internal_status_id, next_internal_status_id,
        line_json, updated_at
    )
    SELECT d_id, log_id, o_id,
           previous_internal_status_id, update_internal_status_id, next_internal_status_id,
           el, u_at
    FROM filtered
    ON CONFLICT ON CONSTRAINT uq_status_log_domain_object_updated
    DO UPDATE SET
        line_json                   = EXCLUDED.line_json,
        log_id                      = EXCLUDED.log_id,
        previous_internal_status_id = EXCLUDED.previous_internal_status_id,
        update_internal_status_id   = EXCLUDED.update_internal_status_id,
        next_internal_status_id     = EXCLUDED.next_internal_status_id;

    SELECT MAX((el->>'log_id')::text) INTO v_last_status_log_id
    FROM jsonb_array_elements(p_param_json) AS el;

    IF v_last_status_log_id IS NOT NULL THEN
        UPDATE mapping.persistent_vars
        SET value = v_last_status_log_id
        WHERE key = 'last_status_log_id';
    END IF;

    IF NOT p_no_results THEN
        RETURN QUERY
        SELECT sl.status_log_id, sl.domain_id, sl.object_id, sl.line_json
        FROM mapping.status_log sl
        WHERE sl.object_id IN (
            SELECT (el->>'object_id')::integer
            FROM jsonb_array_elements(p_param_json) AS el
        );
    END IF;
END;
$$;

alter function crud_status_log(jsonb, boolean) owner to xfw3;

