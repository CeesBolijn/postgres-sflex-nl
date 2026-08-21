create function mapping.get_orderlines(p_order_id integer) returns TABLE(production_orderline_id integer, sales_orderline_id integer, production_order_id integer, order_id integer, order_number integer, number text, sequence integer, material_id integer, material_name text, product_width numeric, product_height numeric, product_amount numeric, product_unit_code text, product_unit_quantity numeric, sqm numeric, internal_status_code text, production_order_status text, production_company_id integer, production_date date, order_date date, production_location text, order_location text)
	stable
	language plpgsql
as $$
BEGIN
    RETURN QUERY
    SELECT
        cs.production_orderline_id,
        cs.sales_orderline_id,
        cs.production_order_id,
        cs.order_id,
        cs.order_number,
        cs.number,
        cs.sequence,
        cs.material_id,
        (SELECT m.line_json->>'material_name'
         FROM mapping.material_production_line m
         WHERE m.material_id = cs.material_id
         LIMIT 1),
        cs.product_width,
        cs.product_height,
        cs.product_amount,
        cs.product_unit_code,
        cs.product_unit_quantity,
        cs.sqm,
        cs.internal_status_code,
        cs.production_order_status,
        cs.production_company_id,
        cs.production_date::date,
        cs.order_date::date,
        cs.production_location,
        cs.order_location
    FROM mapping.component_specs cs
    WHERE cs.order_id = p_order_id
    ORDER BY cs.sequence;
END;
$$;

alter function mapping.get_orderlines(integer) owner to xfw3;

