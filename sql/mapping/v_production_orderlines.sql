create view v_production_orderlines(component_specs_id, production_orderline_id, production_order_id, order_id, customer_id, order_type_id, domain_id, number, order_number, customer_reference, product_internal_title, production_order_sequence, production_orderline_sequence, production_order_status, internal_status_code, material_id, first_production_line_id, product_height, product_width, product_amount, product_unit_code, product_unit_quantity, production_hours, production_company_id, production_location, order_location, order_date, shipment_date, logistics_date, production_date, orderline_updated_at, sqm, is_open, is_dibond_override, resolved_production_line_id, sales_orderline_id, uploader_data_id, state_json, company_name, team_name, quality_check, binned, project_order_checked, assembled, assembled_production, allow_rerouting, unloading_forklift_available, effective_line_id, effective_model, bucket, bucket_date, level, status_sequence, time_on_status_hours, production_order, material_name, status_name) as
	WITH dates AS (
         SELECT CURRENT_DATE AS today,
                CASE EXTRACT(isodow FROM CURRENT_DATE)
                    WHEN 5 THEN CURRENT_DATE + 3
                    WHEN 6 THEN CURRENT_DATE + 2
                    WHEN 7 THEN CURRENT_DATE + 1
                    ELSE CURRENT_DATE + 1
                END AS tomorrow,
                CASE EXTRACT(isodow FROM CURRENT_DATE)
                    WHEN 4 THEN CURRENT_DATE + 4
                    WHEN 5 THEN CURRENT_DATE + 4
                    WHEN 6 THEN CURRENT_DATE + 3
                    WHEN 7 THEN CURRENT_DATE + 2
                    ELSE CURRENT_DATE + 2
                END AS day_after_tomorrow
        )
 SELECT cs.component_specs_id,
    cs.production_orderline_id,
    cs.production_order_id,
    cs.order_id,
    cs.customer_id,
    cs.order_type_id,
    cs.domain_id,
    cs.number,
    cs.order_number,
    cs.customer_reference,
    cs.product_internal_title,
    cs.production_order_sequence,
    cs.production_orderline_sequence,
    cs.production_order_status,
    cs.internal_status_code,
    cs.material_id,
    cs.first_production_line_id,
    cs.product_height,
    cs.product_width,
    cs.product_amount,
    cs.product_unit_code,
    cs.product_unit_quantity,
    cs.production_hours,
    cs.production_company_id,
    cs.production_location,
    cs.order_location,
    cs.order_date,
    cs.shipment_date,
    cs.logistics_date,
    cs.production_date,
    cs.orderline_updated_at,
    cs.sqm,
    cs.is_open,
    cs.is_dibond_override,
    cs.resolved_production_line_id,
    cs.sales_orderline_id,
    cs.uploader_data_id,
    cs.state_json,
    cs.company_name,
    cs.team_name,
    cs.quality_check,
    cs.binned,
    cs.project_order_checked,
    cs.assembled,
    cs.assembled_production,
    cs.allow_rerouting,
    cs.unloading_forklift_available,
        CASE
            WHEN cs.is_dibond_override THEN sh.line_id
            ELSE cs.first_production_line_id
        END AS effective_line_id,
        CASE
            WHEN cs.is_dibond_override THEN sh.model
            ELSE pl_first.model
        END AS effective_model,
        CASE
            WHEN cs.logistics_date::date < d.today THEN 'overdue'::text
            WHEN cs.logistics_date::date = d.today THEN 'today'::text
            WHEN cs.logistics_date::date = d.tomorrow THEN 'tomorrow'::text
            WHEN cs.logistics_date::date = d.day_after_tomorrow THEN 'day_after_tomorrow'::text
            ELSE NULL::text
        END AS bucket,
        CASE
            WHEN cs.logistics_date::date < d.today THEN NULL::date
            ELSE cs.logistics_date::date
        END AS bucket_date,
    i.level,
    i.sequence AS status_sequence,
    EXTRACT(epoch FROM (now() AT TIME ZONE 'Europe/Amsterdam'::text)::timestamp with time zone - (cs.orderline_updated_at AT TIME ZONE 'Europe/Amsterdam'::text)) / 3600::numeric AS time_on_status_hours,
    concat(cs.number, 'P', cs.production_order_sequence) AS production_order,
    mpl.line_json ->> 'name'::text AS material_name,
    i.code::text AS status_name
   FROM mapping.component_specs cs
     CROSS JOIN dates d
     JOIN mapping.internal_status i ON i.code::text = cs.internal_status_code
     LEFT JOIN relation.production_line pl_first ON pl_first.line_id = cs.first_production_line_id
     LEFT JOIN relation.production_line sh ON sh.line = 'Sheet'::text
     LEFT JOIN LATERAL ( SELECT mpl2.line_json
           FROM mapping.material_production_line mpl2
          WHERE mpl2.material_id = cs.material_id
         LIMIT 1) mpl ON true
  WHERE (cs.order_type_id = ANY (ARRAY[2, 3, 7])) AND (cs.internal_status_code <> ALL (ARRAY['cancelled'::text, 'file_error'::text])) AND cs.logistics_date::date <= d.day_after_tomorrow AND (cs.logistics_date::date >= d.today OR cs.is_open);

alter table v_production_orderlines owner to xfw3;

