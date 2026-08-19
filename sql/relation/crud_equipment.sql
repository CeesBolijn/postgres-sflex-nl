create function crud_equipment(p_param_json jsonb, p_no_results boolean DEFAULT false) returns TABLE(param_id integer, track_by integer, crud character varying, something text, last_batch_id integer)
	language plpgsql
as $$
DECLARE
    param_record RECORD;
BEGIN
    -- Create temporary table for parameters
    CREATE TEMP TABLE IF NOT EXISTS temp_equipment_params (
        param_id SERIAL,
        track_by INTEGER,
        crud VARCHAR(100),
        something TEXT,
        last_batch_id INTEGER
    ) ON COMMIT DROP;

    -- Insert parameters from JSON
    INSERT INTO temp_equipment_params(
        track_by, crud, something, last_batch_id
    )
    SELECT
        (item->>'trackBy')::INTEGER,
        item->>'crud',
        item->>'something',
        (item->>'lastBatchId')::INTEGER
    FROM jsonb_array_elements(p_param_json) AS item;

    -- Process mutations (placeholder for future implementation)
    FOR param_record IN
        SELECT * FROM temp_equipment_params ORDER BY crud
    LOOP
        -- Placeholder for equipment CRUD operations
        -- Implementation would go here based on business requirements
        NULL;
    END LOOP;

    -- Return results if requested
    IF NOT p_no_results THEN
        RETURN QUERY
        SELECT
            tp.param_id,
            tp.track_by,
            tp.crud,
            tp.something,
            tp.last_batch_id
        FROM temp_equipment_params tp;
    END IF;
END;
$$;

alter function crud_equipment(jsonb, boolean) owner to xfw3;

