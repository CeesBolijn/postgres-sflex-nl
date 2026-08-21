create function mapping.crud_uploader_source_file(p_param_json jsonb, p_no_results boolean DEFAULT false) returns TABLE(uploader_source_file_id bigint, uploader_data_id bigint, production_filename text, converted_preview_medium_url text)
	language plpgsql
as $$
#variable_conflict use_column
DECLARE
    v_last_updated_at timestamp;
BEGIN
    INSERT INTO mapping.uploader_source_file (
        uploader_source_file_id, uploader_data_id, production_filename,
        converted_preview_medium_url, updated_at
    )
    SELECT
        (el->>'uploader_source_file_id')::bigint,
        (el->>'uploader_data_id')::bigint,
        el->>'production_filename',
        el->>'converted_preview_medium_url',
        (el->>'updated_at')::timestamptz
    FROM jsonb_array_elements(p_param_json) AS el
    ON CONFLICT ON CONSTRAINT pk_uploader_source_file
    DO UPDATE SET
        uploader_data_id             = EXCLUDED.uploader_data_id,
        production_filename          = EXCLUDED.production_filename,
        converted_preview_medium_url = EXCLUDED.converted_preview_medium_url,
        updated_at                   = EXCLUDED.updated_at;

    -- Store the sync watermark for the next incremental fetch.
    -- Kept as a naive timestamp: the value is written to a text column and
    -- interpolated into a MySQL DATETIME literal, which rejects a timezone
    -- offset under strict sql_mode (error 1525).
    SELECT MAX((el->>'updated_at')::timestamp) - interval '15 seconds'
    INTO v_last_updated_at
    FROM jsonb_array_elements(p_param_json) AS el;

    IF v_last_updated_at IS NOT NULL THEN
        UPDATE mapping.persistent_vars
        SET value = v_last_updated_at::text
        WHERE key = 'last_uploader_source_file_updated_at';
    END IF;

    IF NOT p_no_results THEN
        RETURN QUERY
        SELECT usf.uploader_source_file_id, usf.uploader_data_id,
               usf.production_filename, usf.converted_preview_medium_url
        FROM mapping.uploader_source_file usf
        WHERE usf.uploader_source_file_id IN (
            SELECT (el->>'uploader_source_file_id')::bigint
            FROM jsonb_array_elements(p_param_json) AS el
        );
    END IF;
END;
$$;

alter function mapping.crud_uploader_source_file(jsonb, boolean) owner to xfw3;

