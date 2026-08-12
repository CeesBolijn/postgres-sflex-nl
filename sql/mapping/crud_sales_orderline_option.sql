create function crud_sales_orderline_option(p_param_json jsonb, p_no_results boolean DEFAULT false) returns TABLE(param_id integer, track_by integer, crud text, domain_id integer, id integer, sales_orderline_id integer, option_type_code text, option_title_base text, option_internal_description text, option_input_value text, parent_type_code text, parent_title_base text, option_codes text[], updated_at timestamp without time zone)
	language plpgsql
as $$
#variable_conflict use_column
DECLARE
    last_updated timestamp;
BEGIN

    CREATE TEMP TABLE param_table ON COMMIT DROP AS
    SELECT
        row_number() OVER ()::integer AS param_id,
        (el->>'track_by')::integer AS track_by,
        el->>'crud' AS crud,
        (el->>'domain_id')::integer AS domain_id,
        (el->>'id')::integer AS id,
        (el->>'sales_orderline_id')::integer AS sales_orderline_id,
        el->>'option_type_code' AS option_type_code,
        el->>'option_title_base' AS option_title_base,
        el->>'option_internal_description' AS option_internal_description,
        el->>'option_input_value' AS option_input_value,
        el->>'parent_type_code' AS parent_type_code,
        el->>'parent_title_base' AS parent_title_base,
        LOWER(el->>'api_code') AS api_code,
        LOWER(el->>'product_api_code') AS product_api_code,
        (el->>'updated_at')::timestamp AS updated_at
    FROM jsonb_array_elements(p_param_json) AS el;

    INSERT INTO mapping.sales_orderline_option AS soo (
        domain_id, id, sales_orderline_id, option_type_code, option_title_base,
        option_internal_description, option_input_value, parent_type_code, parent_title_base,
        option_codes, updated_at, api_code, product_api_code
    )
    SELECT
        pt.domain_id, pt.id, pt.sales_orderline_id, pt.option_type_code, pt.option_title_base,
        pt.option_internal_description, pt.option_input_value, pt.parent_type_code, pt.parent_title_base,
        ot.option_codes, pt.updated_at, pt.api_code, pt.product_api_code
    FROM param_table pt
    -- One legacy product/option pair carries its new option codes as an array on
    -- a single translation row: the unique index on (product_api_code, api_code)
    -- guarantees at most one match, so the array is taken as stored.
    LEFT JOIN mapping.option_translation ot
           ON ot.product_api_code = pt.product_api_code
          AND ot.api_code         = pt.api_code
    WHERE pt.crud = 'merge'
    ON CONFLICT ON CONSTRAINT sales_orderline_option_pkey DO UPDATE SET
        sales_orderline_id          = EXCLUDED.sales_orderline_id,
        option_type_code            = EXCLUDED.option_type_code,
        option_title_base           = EXCLUDED.option_title_base,
        option_internal_description = EXCLUDED.option_internal_description,
        option_input_value          = EXCLUDED.option_input_value,
        parent_type_code            = EXCLUDED.parent_type_code,
        parent_title_base           = EXCLUDED.parent_title_base,
        -- keep the existing codes when no translation matched, so a missing
        -- crosswalk entry does not wipe a previously resolved set
        option_codes                = COALESCE(EXCLUDED.option_codes, soo.option_codes),
        updated_at                  = EXCLUDED.updated_at,
        api_code                    = EXCLUDED.api_code,
        product_api_code            = EXCLUDED.product_api_code;

    SELECT MAX(pt.updated_at)
    INTO last_updated
    FROM param_table pt;

    IF last_updated IS NOT NULL THEN
        UPDATE mapping.persistent_vars
        SET value = last_updated
        WHERE key = 'last_sales_orderline_option_updated_at';
    END IF;

    PERFORM mapping.create_spec_unit_manifest(
        (SELECT array_agg(DISTINCT cs.production_orderline_id)
         FROM   param_table pt
         JOIN   mapping.component_specs cs
                ON cs.sales_orderline_id = pt.sales_orderline_id
         WHERE  pt.crud = 'merge')
    );

    IF NOT p_no_results THEN
        RETURN QUERY
        SELECT
            pt.param_id, pt.track_by, pt.crud, pt.domain_id,
            pt.id, pt.sales_orderline_id, pt.option_type_code, pt.option_title_base,
            pt.option_internal_description, pt.option_input_value, pt.parent_type_code,
            pt.parent_title_base, soo.option_codes, pt.updated_at
        FROM param_table pt
        LEFT JOIN mapping.sales_orderline_option soo
            ON soo.id = pt.id
        ORDER BY pt.param_id;
    END IF;

END;
$$;

alter function crud_sales_orderline_option(jsonb, boolean) owner to xfw3;

