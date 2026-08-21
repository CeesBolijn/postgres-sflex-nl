create function mapping.get_sitrep_detail(p_day_offset integer, p_model text DEFAULT NULL::text, p_models text[] DEFAULT NULL::text[], p_page integer DEFAULT 1, p_page_size integer DEFAULT 100) returns TABLE(orderline_id integer, sales_orderline_id integer, production_order_id integer, order_id integer, order_number integer, number text, sequence integer, material_id integer, material_name text, product_width numeric, product_height numeric, product_amount numeric, product_unit_code text, product_unit_quantity numeric, sqm numeric, internal_status_code text, production_order_status text, production_company_id integer, production_date date, order_date date, production_location text, order_location text, bucket text, bucket_date date, production_line jsonb, is_open boolean, status_sequence integer)
	stable
	language plpgsql
as $$
DECLARE
    v_models      text[]  := COALESCE(p_models, ARRAY[p_model]);
    v_page        integer := COALESCE(NULLIF(p_page, 0), 1);
    v_page_size   integer := COALESCE(NULLIF(p_page_size, 0), 100);
    v_offset      integer := (v_page - 1) * v_page_size;
    v_bucket      text    :=
    CASE p_day_offset
       WHEN 0 THEN 'overdue'
       WHEN 1 THEN 'today'
       WHEN 2 THEN 'tomorrow'
       WHEN 3 THEN 'day_after_tomorrow'
    END;
    v_prod_lines  jsonb;
BEGIN
    IF v_bucket IS NULL THEN
        RAISE EXCEPTION 'invalid p_day_offset: %, expected 0..3', p_day_offset;
    END IF;

    SELECT lookup_json INTO v_prod_lines
      FROM relation.lookup
     WHERE lookup = 'lookup_production_line';

    RETURN QUERY
    WITH prod_lines AS (
        SELECT el->>'code' AS code, el->'i18n' AS i18n
        FROM jsonb_array_elements(v_prod_lines) AS el
    ),
    filtered AS (
        SELECT
            v.order_id,
            v.bucket,
            v.bucket_date,
            v.effective_line_id,
            v.is_open,
            v.status_sequence,
            v.sqm
        FROM mapping.v_production_orderlines v
        WHERE v.bucket = v_bucket
          AND v.effective_model = ANY(v_models)
    )
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
        cs.order_location,
        f.bucket,
        f.bucket_date,
        pl_i18n.i18n                          AS production_line,
        f.is_open,
        f.status_sequence
    FROM filtered f
    JOIN mapping.component_specs cs        ON cs.order_id = f.order_id
    LEFT JOIN relation.production_line rpl ON rpl.line_id = f.effective_line_id
    LEFT JOIN prod_lines pl_i18n           ON pl_i18n.code = rpl.line_json::jsonb->>'code'
    ORDER BY f.bucket_date NULLS FIRST, cs.order_id, cs.sequence
    LIMIT v_page_size OFFSET v_offset;
END;
$$;

alter function mapping.get_sitrep_detail(integer, text, text[], integer, integer) owner to xfw3;

