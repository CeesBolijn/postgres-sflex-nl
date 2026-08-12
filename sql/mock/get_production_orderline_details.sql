create function get_production_orderline_details(p_production_line_id integer) returns TABLE(production_orderline_id integer, order_id integer, material_id integer, internal_status_code text, status_sequence integer, product_amount numeric, sqm numeric, has_rework boolean, rework_amount numeric, rework_sqm numeric, order_log_ids integer[], production_date timestamp without time zone, cutoff_time timestamp without time zone, duration_seconds integer, class_name text[])
	language plpgsql
as $$
#variable_conflict use_column
DECLARE
    v_max_sequence integer := 450;
BEGIN
    RETURN QUERY
    WITH ir_grouped AS (
        SELECT
            ir.production_orderline_id,
            ir.order_id,
            SUM(ir.object_amount)::numeric                AS rework_amount,
            array_agg(ir.order_log_id)                    AS order_log_ids,
            bool_or(ir.production_line_id IS NOT NULL)    AS has_rework
        FROM mapping.internal_rework ir
        WHERE ir.deleted_at IS NULL
        GROUP BY ir.production_orderline_id, ir.order_id
    ),
    today AS (
        SELECT (now() AT TIME ZONE 'Europe/Amsterdam')::date AS l_date
    )
    SELECT
        cs.production_orderline_id,
        cs.order_id,
        cs.material_id,
        cs.internal_status_code,
        isc.sequence                                      AS status_sequence,
        cs.product_amount,
        cs.sqm,
        COALESCE(ir.has_rework, false)                     AS has_rework,
        ir.rework_amount,
        CASE
            WHEN ir.rework_amount IS NOT NULL
            THEN cs.sqm / NULLIF(cs.product_amount, 0) * ir.rework_amount
        END                                                AS rework_sqm,
        ir.order_log_ids,
        cs.production_date,
        -- Only the wall-clock time is used; the stored timetz offset is ignored,
        -- since cut_off_time is defined as an Amsterdam local time, not a fixed UTC offset.
        (t.l_date + ct.cut_off_time::time)                 AS cutoff_time,
        EXTRACT(EPOCH FROM (
            cs.production_date - (t.l_date + ct.cut_off_time::time)
        ))::integer                                        AS duration_seconds,
        array_remove(ARRAY[
            CASE
                WHEN isc.sequence < v_max_sequence
                     AND cs.production_date - now() < make_interval(secs => ct.nest_rip_window_seconds)
                THEN 'plan-alert'
                WHEN isc.sequence < v_max_sequence
                THEN 'plan-warning'
            END,
            CASE WHEN ir.has_rework THEN 'plan-signal' END
        ], NULL)                                           AS class_name
    FROM mapping.component_specs cs
    CROSS JOIN today t
    JOIN mapping.internal_status isc
        ON isc.code = cs.internal_status_code
    LEFT JOIN ir_grouped ir
        ON ir.production_orderline_id = cs.production_orderline_id
    LEFT JOIN legacy.cutoff_times ct
        ON ct.delivery_hours = cs.production_hours
    WHERE cs.is_open = true
      AND cs.first_production_line_id = p_production_line_id;
END;
$$;

alter function get_production_orderline_details(integer) owner to xfw3;

