create function get_batch(p_batch_id integer) returns TABLE(batch_at timestamp with time zone, batch_id integer, nest_id integer, nest_name text, amount integer, nest_width integer, nest_height integer, batch_name text, source text, width numeric, height numeric, original_amount integer, filename text, production_orderline_id integer, sales_orderline_id integer, production_order_id integer, order_id integer, number text, sequence integer, sqm numeric, internal_status_code text, production_order_status text, production_company_id integer, production_date date, order_date date, production_location text, order_location text)
	stable
	language sql
as $$
    SELECT
        b.batch_at,
        b.batch_id,
        n.nest_id,
        n.nest_name,
        n.amount,
        n.width                                                   AS nest_width,
        n.height                                                  AS nest_height,
        (b.batch_json->>'name')::text                             AS batch_name,
        (n.nest_json->>'source')::text                            AS source,
        (sp.single_product_json->>'width')::numeric               AS width,
        (sp.single_product_json->>'height')::numeric              AS height,
        (sp.single_product_json->>'original_amount')::int         AS original_amount,
        (sp.single_product_json->>'filename')::text               AS filename,
        cs.production_orderline_id,
        cs.sales_orderline_id,
        cs.production_order_id,
        cs.order_id,
        cs.number,
        cs.sequence,
        cs.sqm,
        cs.internal_status_code,
        cs.production_order_status,
        cs.production_company_id,
        cs.production_date::date,
        cs.order_date::date,
        cs.production_location,
        cs.order_location
    FROM legacy.nest n
    JOIN legacy.batch b
        ON n.batch_uid = b.batch_uid
    JOIN legacy.single_product sp
        ON n.nest_id = sp.nest_id
    JOIN mapping.component_specs cs
        ON (sp.single_product_json->>'production_orderline_id')::int = cs.production_orderline_id
    WHERE b.batch_id = p_batch_id;
$$;

alter function get_batch(integer) owner to xfw3;

