create function get_material_planning_aggregate(p_production_line_id integer) returns TABLE(material_id integer, ready_to_nest_count bigint, ready_to_nest_product_amount numeric, ready_to_nest_sqm numeric, needs_dtp_count bigint, needs_dtp_product_amount numeric, needs_dtp_sqm numeric, rework_lines_count bigint, rework_amount numeric, rework_sqm numeric, class_name text[])
	language plpgsql
as $$
#variable_conflict use_column
BEGIN
    RETURN QUERY
    WITH d AS (
        SELECT * FROM mock.get_production_orderline_details(p_production_line_id)
    )
    SELECT
        d.material_id,
        count(*) FILTER (
            WHERE d.status_sequence BETWEEN 450 AND 495 AND NOT d.has_rework
        )                                                              AS ready_to_nest_count,
        sum(d.product_amount) FILTER (
            WHERE d.status_sequence BETWEEN 450 AND 495 AND NOT d.has_rework
        )                                                              AS ready_to_nest_product_amount,
        sum(d.sqm) FILTER (
            WHERE d.status_sequence BETWEEN 450 AND 495 AND NOT d.has_rework
        )                                                              AS ready_to_nest_sqm,
        count(*) FILTER (
            WHERE d.status_sequence < 450 AND NOT d.has_rework
        )                                                              AS needs_dtp_count,
        sum(d.product_amount) FILTER (
            WHERE d.status_sequence < 450 AND NOT d.has_rework
        )                                                              AS needs_dtp_product_amount,
        sum(d.sqm) FILTER (
            WHERE d.status_sequence < 450 AND NOT d.has_rework
        )                                                              AS needs_dtp_sqm,
        count(*) FILTER (WHERE d.has_rework)                          AS rework_lines_count,
        sum(d.rework_amount) FILTER (WHERE d.has_rework)              AS rework_amount,
        sum(d.rework_sqm) FILTER (WHERE d.has_rework)                 AS rework_sqm,
        -- Unnest per row via LATERAL first, then aggregate distinct.
        -- array_agg() directly on an array column fails with "cannot accumulate
        -- empty arrays" as soon as one row has class_name = '{}'.
        array_remove(array_agg(DISTINCT cn.value), NULL)               AS class_name
    FROM d
    LEFT JOIN LATERAL unnest(d.class_name) AS cn(value) ON true
    GROUP BY d.material_id
    ORDER BY d.material_id;
END;
$$;

alter function get_material_planning_aggregate(integer) owner to xfw3;

