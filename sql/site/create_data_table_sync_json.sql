create function site.create_data_table_sync_json(p_data_table character varying) returns void
	language plpgsql
as $$
DECLARE
    v_data_table_json JSONB := '[{
        "src": null,
        "queryParams": [],
        "procedure": null,
        "data": [],
        "originalData": [],
        "primaryKeys": [],
        "foreignKeys": [],
        "fields": []
    }]'::JSONB;
    v_stored_proc VARCHAR(200);
    v_param_json TEXT;
BEGIN
    -- Set the src field
    v_data_table_json := jsonb_set(v_data_table_json, '{0,src}', to_jsonb(p_data_table));

    -- Get stored procedure name
    SELECT stored_proc INTO v_stored_proc
    FROM site.data_table
    WHERE data_table = p_data_table;

    IF v_stored_proc IS NOT NULL THEN
        v_data_table_json := jsonb_set(v_data_table_json, '{0,procedure}', to_jsonb(v_stored_proc));
    END IF;

    -- Get query parameters
    SELECT param_json INTO v_param_json
    FROM site.data_table
    WHERE data_table = p_data_table;

    IF v_param_json IS NOT NULL THEN
        v_data_table_json := jsonb_set(v_data_table_json, '{0,queryParams}', v_param_json::JSONB);
    END IF;

    -- Update the data table with the JSON
    UPDATE site.data_table
    SET data_table_json = v_data_table_json::TEXT
    WHERE data_table = p_data_table;
END;
$$;

alter function site.create_data_table_sync_json(varchar) owner to xfw3;

