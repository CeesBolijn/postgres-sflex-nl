create function get_components_inflow_aggregated(p_from date, p_line_type text, p_domain_id integer, p_look_ahead_days integer DEFAULT 10, p_threshold integer DEFAULT 1) returns TABLE(threshold integer, production_line_id integer, line text, material_ids integer[], material_names text[], class_name jsonb, totals_json jsonb, cards_json jsonb)
	stable
	language plpgsql
as $$
#variable_conflict use_column
BEGIN
    RETURN QUERY
    WITH gci AS (
        SELECT *
        FROM job.get_components_inflow(p_from, p_line_type, p_domain_id, p_look_ahead_days, p_threshold)
    ),
    totals AS (
        SELECT
            g.material_ids,
            g.production_line_id,
            g.is_rework,
            (CASE WHEN g.is_rework THEN true ELSE (g.piece_code = 'all') END) AS within_48h,
            count(DISTINCT g.group_key) AS order_count,
            sum(g.sqm) AS total_sqm
        FROM gci g
        GROUP BY g.material_ids, g.production_line_id, g.is_rework,
                 (CASE WHEN g.is_rework THEN true ELSE (g.piece_code = 'all') END)
    ),
    totals_agg AS (
        SELECT
            t.material_ids,
            t.production_line_id,
            jsonb_agg(
                jsonb_build_object(
                    'is_rework', t.is_rework,
                    'within_48h', t.within_48h,
                    'order_count', t.order_count,
                    'total_sqm', round(t.total_sqm, 1)
                )
                ORDER BY t.is_rework, t.within_48h
            ) AS totals_json
        FROM totals t
        GROUP BY t.material_ids, t.production_line_id
    ),
    class_agg AS (
        SELECT
            g.material_ids,
            g.production_line_id,
            jsonb_agg(DISTINCT elem.value) FILTER (WHERE elem.value IS NOT NULL) AS class_name
        FROM gci g
        LEFT JOIN LATERAL jsonb_array_elements(coalesce(g.class_name, '[]'::jsonb)) AS elem(value) ON true
        GROUP BY g.material_ids, g.production_line_id
    ),
    card_metrics AS (
        SELECT
            g.material_ids,
            g.production_line_id,
            g.nest_date,
            g.nest_status,
            g.is_rework,
            g.ship_separately,
            g.group_key,
            g.piece_code,
            g.cutoff_time,
            (CASE WHEN g.ship_separately THEN g.order_id END) AS order_id,
            min(g.nest_time) AS nest_time,
            min(g.production_hours) AS production_hours,
            count(DISTINCT g.group_key) AS order_count,
            sum(g.sqm) AS total_sqm
        FROM gci g
        GROUP BY
            g.material_ids, g.production_line_id, g.nest_date, g.nest_status, g.is_rework,
            g.ship_separately, g.group_key, g.piece_code, g.cutoff_time,
            (CASE WHEN g.ship_separately THEN g.order_id END)
    ),
    card_agg AS (
        SELECT
            cm.material_ids,
            cm.production_line_id,
            cm.nest_date,
            jsonb_agg(
                jsonb_build_object(
                    'nest_status', cm.nest_status,
                    'nest_time', cm.nest_time,
                    'production_hours', cm.production_hours,
                    'cutoff_time', cm.cutoff_time,
                    'piece_code', cm.piece_code,
                    'is_rework', cm.is_rework,
                    'ship_separately', cm.ship_separately,
                    'order_id', cm.order_id,
                    'order_count', cm.order_count,
                    'total_sqm', round(cm.total_sqm, 1)
                )
                ORDER BY cm.nest_status, cm.piece_code, cm.cutoff_time, cm.is_rework, cm.order_id
            ) AS items_json
        FROM card_metrics cm
        GROUP BY cm.material_ids, cm.production_line_id, cm.nest_date
    ),
    cards_agg AS (
        SELECT
            ca.material_ids,
            ca.production_line_id,
            jsonb_agg(
                jsonb_build_object('nest_date', ca.nest_date, 'items', ca.items_json)
                ORDER BY ca.nest_date
            ) AS cards_json
        FROM card_agg ca
        GROUP BY ca.material_ids, ca.production_line_id
    ),
    names_agg AS (
        SELECT
            ta.material_ids,
            ta.production_line_id,
            array_agg(mpl.material_name ORDER BY elem.ord) AS material_names
        FROM totals_agg ta
        CROSS JOIN LATERAL unnest(ta.material_ids) WITH ORDINALITY AS elem(value, ord)
        LEFT JOIN (
            SELECT DISTINCT ON (m.material_id)
                m.material_id,
                m.line_json->>'material_name' AS material_name
            FROM mapping.material_production_line m
            ORDER BY m.material_id
        ) mpl
            ON mpl.material_id = elem.value
        GROUP BY ta.material_ids, ta.production_line_id
    )
    SELECT
        p_threshold AS threshold,
        ta.production_line_id,
        p_line_type AS line,
        ta.material_ids,
        na.material_names,
        coalesce(ca_class.class_name, '[]'::jsonb) AS class_name,
        ta.totals_json,
        coalesce(cd.cards_json, '[]'::jsonb) AS cards_json
    FROM totals_agg ta
    LEFT JOIN names_agg na
        ON na.material_ids = ta.material_ids
       AND na.production_line_id = ta.production_line_id
    LEFT JOIN class_agg ca_class
        ON ca_class.material_ids = ta.material_ids
       AND ca_class.production_line_id = ta.production_line_id
    LEFT JOIN cards_agg cd
        ON cd.material_ids = ta.material_ids
       AND cd.production_line_id = ta.production_line_id
    ORDER BY ta.material_ids, ta.production_line_id;
END;
$$;

alter function get_components_inflow_aggregated(date, text, integer, integer, integer) owner to xfw3;

