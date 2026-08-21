create function mapping.crud_product(p_param_json jsonb, p_no_results boolean DEFAULT false) returns TABLE(product_id integer, material_id integer, production_start_date date, production_interval integer)
	language plpgsql
as $$
BEGIN
    -- Remove products that were soft deleted in the source system
    DELETE FROM mapping.product p
    WHERE p.product_id IN (
        SELECT (el->>'product_id')::integer
        FROM jsonb_array_elements(p_param_json) AS el
        WHERE el->>'deleted_at' IS NOT NULL
    );

    INSERT INTO mapping.product (product_id, material_id, production_start_date, production_interval)
    SELECT
        (el->>'product_id')::integer,
        (el->>'material_id')::integer,
        (el->>'production_start_date')::date,
        (el->>'production_interval')::integer
    FROM jsonb_array_elements(p_param_json) AS el
    WHERE el->>'deleted_at' IS NULL
    ON CONFLICT ON CONSTRAINT pk_mapping_product DO UPDATE
    SET material_id           = EXCLUDED.material_id,
        production_start_date = EXCLUDED.production_start_date,
        production_interval   = EXCLUDED.production_interval,
        updated_at           = now();

    IF NOT p_no_results THEN
        RETURN QUERY
        SELECT p.product_id, p.material_id, p.production_start_date, p.production_interval
        FROM mapping.product p
        WHERE p.product_id IN (
            SELECT (el->>'product_id')::integer
            FROM jsonb_array_elements(p_param_json) AS el
            WHERE el->>'deleted_at' IS NULL
        );
    END IF;
END;
$$;

alter function mapping.crud_product(jsonb, boolean) owner to xfw3;

