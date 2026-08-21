create function legacy.crud_container_status(p_param_json jsonb DEFAULT '[]'::jsonb, p_no_results boolean DEFAULT false) returns TABLE(param_id integer, track_by integer, crud character varying, container_id integer, new_state boolean)
	language plpgsql
as $$
DECLARE
    param_table RECORD;
BEGIN

    INSERT INTO legacy.log (log_json, type, content_id) VALUES (p_param_json, 'ContainerStatusUpdate', gen_random_uuid());

    -- Validate that p_param_json is an array
    IF jsonb_typeof(p_param_json) != 'array' THEN
        RAISE EXCEPTION 'p_param_json must be a JSON array, got: %', jsonb_typeof(p_param_json);
    END IF;

    -- Process each record
    FOR param_table IN
        SELECT *
        FROM jsonb_to_recordset(p_param_json) AS t(
                param_id INTEGER,
                track_by INT,
                crud VARCHAR,
                "containerId" INT, -- Match your JSON field name
                "newState" BOOLEAN -- Match your JSON field name
        )
        LOOP
            IF param_table.crud = 'update' THEN
                -- Update the container status
                UPDATE legacy.containers
                SET status = param_table."newState",
                    last_update = now()
                WHERE legacy.containers.container_id = param_table."containerId";

                -- Log the update action
                INSERT INTO legacy.log (log_json, type, content_id)
                VALUES (jsonb_build_object(
                                'containerId', param_table."containerId",
                                'newState', param_table."newState"
                        ),
                    'ContainerStatusUpdate',
                    gen_random_uuid()
                );
            END IF;
        END LOOP;

    IF NOT p_no_results THEN
        RETURN QUERY
            SELECT t.param_id,
                   t.track_by,
                   t.crud,
                   t."containerId" AS container_id,
                   t."newState"    AS new_state
            FROM jsonb_to_recordset(p_param_json) AS t(
                param_id INTEGER,
                track_by INT,
                crud VARCHAR,
                "containerId" INT,
                "newState" BOOLEAN
            );
    END IF;
END;
$$;

alter function legacy.crud_container_status(jsonb, boolean) owner to xfw3;

