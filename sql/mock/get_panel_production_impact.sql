create function get_panel_production_impact(p_material_id integer, p_from date, p_until date, p_speed_m_second numeric, p_velocity_m_s2 numeric, p_waste_perc numeric DEFAULT 0.22) returns jsonb
	language plpgsql
as $$
#variable_conflict use_column
DECLARE
    v_result jsonb;
BEGIN
    WITH panel AS (
        SELECT
            (material_production_line.line_json->'specs'->0->>'width')::numeric  AS panel_width_cm,
            (material_production_line.line_json->'specs'->0->>'height')::numeric AS panel_height_cm
        FROM mapping.material_production_line
        WHERE material_production_line.material_id = p_material_id
    ),
    lines AS (
        SELECT
            (component_specs.product_width * component_specs.product_height) / 10000.0 AS area_m2,
            ntile(4) OVER (ORDER BY (component_specs.product_width * component_specs.product_height ) DESC) AS quartile
        FROM mapping.component_specs
        WHERE component_specs.is_open = true
          AND component_specs.production_date BETWEEN p_from AND p_until
          AND component_specs.production_order_status = 'file_in_gangrun'
    ),
    totals AS (
        SELECT
            sum(area_m2) AS total_area_m2,
            avg(area_m2) FILTER (WHERE quartile = 4) AS q4_avg_area_m2
        FROM lines
    )
    SELECT evaluate_many_nas(
        '["panel_area_m2 = panel_width_cm * panel_height_cm / 10000",
          "net_area_m2 = panel_area_m2 * (1 - waste_perc)",
          "nest_amount = total_area_m2 / net_area_m2",
          "batch_sqm = nest_amount * panel_area_m2",
          "n_rectangles = net_area_m2 / q4_avg_area_m2",
          "print_impact_s = duration_per_sqm_s * panel_area_m2",
          "coat_impact_s = 50 * max(panel_width_cm, panel_height_cm)",
          "t_width = timeStraightSection(panel_width_cm, max_speed_mps, accel_mps2)",
          "t_height = timeStraightSection(panel_height_cm, max_speed_mps, accel_mps2)",
          "cut_impact_s = n_rectangles * 2 * (t_width + t_height)"]',
        jsonb_build_object(
            'panel_width_cm', panel.panel_width_cm,
            'panel_height_cm', panel.panel_height_cm,
            'waste_perc', p_waste_perc,
            'total_area_m2', totals.total_area_m2,
            'q4_avg_area_m2', totals.q4_avg_area_m2,
            'duration_per_sqm_s', mock.get_material_standard_duration_per_sqm(p_material_id),
            'max_speed_mps', p_speed_m_second,
            'accel_mps2', p_velocity_m_s2
        )::text
    )
    INTO v_result
    FROM panel, totals;

    RETURN jsonb_build_object(
        'sqm', v_result->'batch_sqm',
        'amount', v_result->'nest_amount',
        'steps', jsonb_build_array(
            jsonb_build_object('step', 'print', 'order', 0, 'standard_production_impact', v_result->'print_impact_s'),
            jsonb_build_object('step', 'coat',  'order', 1, 'standard_production_impact', v_result->'coat_impact_s'),
            jsonb_build_object('step', 'cut',   'order', 2, 'standard_production_impact', v_result->'cut_impact_s')
        )
    );
END;
$$;

alter function get_panel_production_impact(integer, date, date, numeric, numeric, numeric) owner to xfw3;

