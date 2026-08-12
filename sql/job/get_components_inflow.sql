create function get_components_inflow(p_from date, p_line_type text, p_domain_id integer, p_look_ahead_days integer DEFAULT 10, p_threshold integer DEFAULT 1) returns TABLE(production_line_id integer, line text, material_ids integer[], material_name text, order_id integer, production_orderline_id integer, ship_separately boolean, group_key text, nest_date date, nest_time time with time zone, nest_day_offset integer, production_hours integer, cutoff_time time with time zone, sequence integer, internal_status_code text, nest_status text, is_rework boolean, product_amount integer, sqm numeric, piece_code text, class_name jsonb)
	stable
	language plpgsql
as $$
#variable_conflict use_column
DECLARE
    v_status_sequence_array int[] := ARRAY[150, 225, 350, 450, 495];
    v_from_ts timestamptz;
    v_lt_file_in_gangrun_alert_time interval := interval '2 hours';
BEGIN
    v_from_ts := (p_from::timestamp + time '21:30:00') AT TIME ZONE 'Europe/Amsterdam';

    RETURN QUERY
    WITH agenda_dates AS (
        SELECT
            mpa.material_id,
            mpa.material_name,
            mpa.production_line_id,
            g.interval_date AS nest_date
        FROM mock.material_print_schedule mpa
        CROSS JOIN LATERAL action.get_interval_dates(
                 mpa.interval_start_date,
                 p_from,
                 mpa.interval_days,
                 p_look_ahead_days,
                 p_day_offset := -1
             ) AS g
        WHERE mpa.line = p_line_type
    ),
    ir_grouped AS (
        SELECT
            ir.production_orderline_id,
            bool_or(ir.production_line_id IS NOT NULL) AS has_rework
        FROM mapping.internal_rework ir
        WHERE ir.deleted_at IS NULL
        GROUP BY ir.production_orderline_id
    ),
    order_lines_base AS (
        SELECT
            cs.order_id,
            cs.production_orderline_id,
            coalesce(cs.ship_separately, false) AS ship_separately,
            cs.nest_date::date AS nest_date,
            cs.nest_date::time::timetz AS nest_time,
            CASE WHEN cs.nest_date::date < p_from THEN -1 ELSE 0 END AS nest_day_offset,
            cs.production_hours,
            cs.sqm,
            cs.product_amount,
            coalesce(ir.has_rework, false) AS is_rework,
            s.sequence,
            s.code AS internal_status_code,
            cs.material_id AS orderline_material_id
        FROM mapping.component_specs cs
        JOIN mapping.internal_status s
            ON s.code = cs.internal_status_code
        LEFT JOIN ir_grouped ir
            ON ir.production_orderline_id = cs.production_orderline_id
        WHERE cs.domain_id = p_domain_id
          AND s.sequence = ANY (v_status_sequence_array)
    ),
    order_lines AS (
        SELECT
            ol.order_id,
            ol.production_orderline_id,
            ol.ship_separately,
            CASE WHEN ol.ship_separately THEN 'order:' || ol.order_id ELSE 'line:' || ol.production_orderline_id END AS group_key,
            ad.material_id,
            ad.material_name,
            ad.production_line_id,
            ol.nest_date,
            ol.nest_time,
            ol.nest_day_offset,
            ol.production_hours,
            ol.sqm,
            ol.product_amount,
            ol.is_rework,
            ol.sequence,
            ol.internal_status_code
        FROM order_lines_base ol
        JOIN agenda_dates ad
            ON ad.material_id = ol.orderline_material_id
           AND ad.nest_date = ol.nest_date
    ),
    group_totals AS (
        SELECT
            ol.group_key,
            ol.material_id,
            ol.nest_date,
            min(ol.nest_time) AS nest_time,
            sum(ol.product_amount)::integer AS total_product_amount
        FROM order_lines ol
        GROUP BY ol.group_key, ol.material_id, ol.nest_date
    ),
    group_piece AS (
        SELECT
            gt.group_key,
            gt.material_id,
            gt.nest_date,
            CASE
                WHEN (
                    (extract(epoch FROM ((gt.nest_date + gt.nest_time) - v_from_ts)) / 3600.0)
                    - (
                        SELECT count(*) * 24
                        FROM action.dates dt
                        WHERE dt.date > v_from_ts::date
                          AND dt.date <= gt.nest_date
                          AND dt.is_weekend
                    )
                ) <= 48 THEN 'all'
                WHEN gt.total_product_amount <= p_threshold THEN 'lte'
                ELSE 'gt'
            END AS piece_code
        FROM group_totals gt
    )
    SELECT
        ol.production_line_id,
        p_line_type AS line,
        ol.material_id,
        ol.material_name,
        ol.order_id,
        ol.production_orderline_id,
        ol.ship_separately,
        ol.group_key,
        ol.nest_date,
        ol.nest_time,
        ol.nest_day_offset,
        ol.production_hours,
        c.cut_off_time AS cutoff_time,
        ol.sequence,
        ol.internal_status_code::text,
        CASE
            WHEN ol.internal_status_code = 'file_in_gangrun' THEN 'file_in_gangrun'
            WHEN ol.internal_status_code = 'dtp' THEN 'dtp'
            ELSE 'not_released'
        END AS nest_status,
        ol.is_rework,
        ol.product_amount::integer,
        round(ol.sqm, 1) AS sqm,
        gp.piece_code,
        to_jsonb(array_remove(ARRAY[
            CASE
                WHEN ol.sequence < 450 THEN
                    CASE
                        WHEN (ol.nest_date + ol.nest_time) - now() <= v_lt_file_in_gangrun_alert_time
                        THEN 'plan-alert'
                        ELSE 'plan-signal'
                    END
            END,
            CASE WHEN ol.is_rework THEN 'plan-warning' END
        ], NULL)) AS class_name
    FROM order_lines ol
    JOIN group_piece gp
        ON gp.group_key = ol.group_key
       AND gp.material_id = ol.material_id
       AND gp.nest_date = ol.nest_date
    LEFT JOIN legacy.cutoff_times c
        ON c.delivery_hours = ol.production_hours
    ORDER BY ol.nest_date, ol.material_id, ol.order_id, ol.production_orderline_id;
END;
$$;

alter function get_components_inflow(date, text, integer, integer, integer) owner to xfw3;

