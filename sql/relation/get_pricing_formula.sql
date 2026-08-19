create function get_pricing_formula(p_item_code character varying) returns jsonb
	language plpgsql
as $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'basePriceFormulaJSON', base_price_formula_json,
        'discountFormulaJSON', discount_formula_json
    )
    INTO v_result
    FROM relation.pricing
    WHERE LEFT(p_item_code, item_code_pattern_len) = item_code_pattern
      AND company_group_id IS NULL
      AND base_price_formula_json IS NOT NULL
    ORDER BY item_code_pattern_len DESC
    LIMIT 1;

    RETURN COALESCE(v_result, '{}'::JSONB);
END;
$$;

alter function get_pricing_formula(varchar) owner to xfw3;

