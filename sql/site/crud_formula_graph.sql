create function site.crud_formula_graph(p_param_json jsonb) returns TABLE(crud character varying, track_by integer, formula_graph_id integer, result jsonb, nodes jsonb, connections jsonb)
	language plpgsql
as $$
DECLARE
    v_param RECORD;
BEGIN
    -- Create temporary table for params
    CREATE TEMP TABLE IF NOT EXISTS params_temp (
        param_id SERIAL,
        formula_graph_id INT,
        crud VARCHAR(100),
        formula_graph_json JSONB,
        nas JSONB,
        result JSONB
    ) ON COMMIT DROP;

    -- Insert into params table
    INSERT INTO params_temp (formula_graph_id, crud, formula_graph_json, nas)
    SELECT
        (original->>'formula_graph_id')::INT,
        original->>'crud',
        original,
        (
            SELECT node->'variables'
            FROM jsonb_array_elements(original->'nodes') AS node
            WHERE node->>'type' = 'start'
            LIMIT 1
        )
    FROM jsonb_array_elements(p_param_json) AS original;

    -- Process each param in order by crud
    FOR v_param IN 
        SELECT param_id, pt.crud, formula_graph_json, pt.formula_graph_id, nas
        FROM params_temp pt
        ORDER BY pt.crud
    LOOP
        IF v_param.crud = 'run' THEN
            UPDATE params_temp
            SET result = evaluate_formula_with_complete_report(site.resolve_subgraphs(v_param.formula_graph_json), v_param.nas)
            WHERE param_id = v_param.param_id;
            
        ELSIF v_param.crud = 'update' THEN
            UPDATE site.formula_graph
            SET formula_graph_json = v_param.formula_graph_json
            WHERE site.formula_graph.formula_graph_id = v_param.formula_graph_id;
            
        ELSIF v_param.crud = 'create' THEN
            INSERT INTO site.formula_graph (formula_graph_json)
            VALUES (v_param.formula_graph_json);
        END IF;
    END LOOP;

    -- Return results
    RETURN QUERY
    SELECT
        'update'::VARCHAR(100),
        1,
        p.formula_graph_id,
        p.result,
        (
            SELECT jsonb_agg(
                CASE 
                    WHEN node->>'type' = 'end' THEN
                        jsonb_set(node, '{result}', to_jsonb('result = ' || (p.result->>'result')))
                    ELSE
                        node
                END
            )
            FROM jsonb_array_elements(p.formula_graph_json->'nodes') AS node
        ),
        p.formula_graph_json->'connections'
    FROM params_temp p;

    DROP TABLE IF EXISTS params_temp;
END;
$$;

alter function site.crud_formula_graph(jsonb) owner to xfw3;

