create function crud_log(p_param_json jsonb DEFAULT '[]'::jsonb, p_no_results boolean DEFAULT false) returns TABLE(param_id integer, track_by integer, crud character varying, log_json jsonb, original_json jsonb, log_type character varying, content_id character varying)
	language plpgsql
as $$
DECLARE
    param_table RECORD;
BEGIN
    -- Validate that paramjson is an array
    IF jsonb_typeof(p_param_json) != 'array' THEN
        RAISE EXCEPTION 'paramjson must be a JSON array, got: %', jsonb_typeof(p_param_json);
    END IF;

    -- Process each record
    FOR param_table IN
        SELECT *
        FROM jsonb_to_recordset(p_param_json) AS t(
                param_id integer,
                track_by integer,
                crud varchar,
                log_json jsonb,
                original_json jsonb,
                log_type varchar,
                content_id varchar
            )
        LOOP
            IF param_table.crud = 'create' THEN
                IF NOT EXISTS (
                    SELECT 1 FROM legacy.log 
                    WHERE type = param_table.log_type 
                      AND log.content_id = param_table.content_id
                ) THEN
                    INSERT INTO legacy.log(log_json, type, content_id)
                    VALUES (param_table.log_json, param_table.log_type, param_table.content_id);
                ELSE
                    UPDATE legacy.log
                    SET log_json = param_table.log_json,
                        last_modified_at = NOW()
                    WHERE type = param_table.log_type 
                      AND log.content_id = param_table.content_id;
                END IF;
            END IF;
        END LOOP;

    IF NOT p_no_results THEN
        RETURN QUERY
        SELECT t.param_id,
               t.track_by,
               t.crud,
               t.log_json,
               t.original_json,
               t.log_type,
               t.content_id
        FROM jsonb_to_recordset(p_param_json) AS t(
            param_id integer,
            track_by integer,
            crud varchar,
            log_json jsonb,
            original_json jsonb,
            log_type varchar,
            content_id varchar
        );
    END IF;
END;
$$;

alter function crud_log(jsonb, boolean) owner to xfw3;

