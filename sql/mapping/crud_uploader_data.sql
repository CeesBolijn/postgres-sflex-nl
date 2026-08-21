create function mapping.crud_uploader_data(p_param_json jsonb, p_no_results boolean DEFAULT false) returns TABLE(uploader_data_id integer, domain_id integer, external_id integer, orderline_id integer, file_amount integer, line_json jsonb)
	language plpgsql
as $$
#variable_conflict use_column
DECLARE
    v_last_updated_at timestamp;
BEGIN
    INSERT INTO mapping.uploader_data (uploader_data_id, domain_id, external_id, orderline_id, file_amount, line_json, updated_at)
    SELECT
        (el->>'uploader_data_id')::integer,
        (el->>'domain_id')::integer,
        (el->>'external_id')::integer,
        (el->>'orderline_id')::integer,
        (
            SELECT count(DISTINCT fn.file_name)
            FROM jsonb_array_elements(d.v_data -> 'products') AS p(product)
            CROSS JOIN LATERAL (
                VALUES
                    (p.product -> 'front_side' -> 'file' ->> 'file_name'),
                    (p.product -> 'back_side'  -> 'file' ->> 'file_name')
            ) AS fn(file_name)
            WHERE fn.file_name IS NOT NULL
        )::integer,
        jsonb_set(el, '{data}', d.v_data),
        (el->>'updated_at')::timestamp
    FROM jsonb_array_elements(p_param_json) AS el
    CROSS JOIN LATERAL (
        SELECT CASE jsonb_typeof(el -> 'data')
                   WHEN 'string' THEN (el ->> 'data')::jsonb
                   ELSE el -> 'data'
               END AS v_data
    ) AS d
    ON CONFLICT ON CONSTRAINT pk_mapping_uploader_data
    DO UPDATE SET
        domain_id    = EXCLUDED.domain_id,
        external_id  = EXCLUDED.external_id,
        orderline_id = EXCLUDED.orderline_id,
        file_amount  = EXCLUDED.file_amount,
        line_json    = EXCLUDED.line_json,
        updated_at   = EXCLUDED.updated_at;

    SELECT MAX((el->>'updated_at')::timestamp) INTO v_last_updated_at
    FROM jsonb_array_elements(p_param_json) AS el;

    IF v_last_updated_at IS NOT NULL THEN
        UPDATE mapping.persistent_vars
        SET value = v_last_updated_at::text
        WHERE key = 'last_uploader_data_updated_at';
    END IF;

    IF NOT p_no_results THEN
        RETURN QUERY
        SELECT ud.uploader_data_id, ud.domain_id, ud.external_id, ud.orderline_id, ud.file_amount, ud.line_json
        FROM mapping.uploader_data ud
        WHERE ud.uploader_data_id IN (
            SELECT (el->>'uploader_data_id')::integer
            FROM jsonb_array_elements(p_param_json) AS el
        );
    END IF;
END;
$$;

alter function mapping.crud_uploader_data(jsonb, boolean) owner to xfw3;

