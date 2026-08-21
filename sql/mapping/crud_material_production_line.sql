create function mapping.crud_material_production_line(p_param_json jsonb, p_no_results boolean DEFAULT false) returns TABLE(domain_id integer, material_id integer, production_line_id integer, line_json jsonb)
	language plpgsql
as $$
BEGIN
    INSERT INTO mapping.material_production_line (domain_id, material_id, production_line_id, line_json)
    SELECT
        (el->>'domain_id')::integer,
        (el->>'material_id')::integer,
        (el->>'production_line_id')::integer,
        el
    FROM jsonb_array_elements(p_param_json) AS el
    ON CONFLICT ON CONSTRAINT uq_material_production_line DO UPDATE
    SET domain_id = EXCLUDED.domain_id,
        line_json  = mapping.material_production_line.line_json || EXCLUDED.line_json;

    IF NOT p_no_results THEN
        RETURN QUERY
        SELECT mpl.domain_id, mpl.material_id, mpl.production_line_id, mpl.line_json
        FROM mapping.material_production_line mpl
        WHERE (mpl.material_id, mpl.production_line_id) IN (
            SELECT (el->>'material_id')::integer, (el->>'production_line_id')::integer
            FROM jsonb_array_elements(p_param_json) AS el
        );
    END IF;
END;
$$;

alter function mapping.crud_material_production_line(jsonb, boolean) owner to xfw3;

