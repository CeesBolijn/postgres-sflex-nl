create function get_production_forecast_material(p_from timestamp with time zone, p_days integer, p_line_type text) returns TABLE(date date, production_line_id integer, production_company_id integer, material_id integer, material_name text, budget_sqm numeric, actual_sqm numeric, forecast_sqm numeric, param_json jsonb)
	language plpgsql
as $$
#variable_conflict use_column
DECLARE
    v_from date := p_from::date;
BEGIN
    RETURN QUERY
    WITH actual AS (
        SELECT
            cs.first_production_line_id      AS production_line_id,
            cs.material_id,
            cs.production_date::date         AS date,
            sum(cs.sqm)                      AS actual_sqm
        FROM mapping.component_specs cs
        WHERE cs.production_date >= v_from
          AND cs.production_date < v_from + p_days
          AND cs.internal_status_code <> 'cancelled'
        GROUP BY cs.first_production_line_id, cs.material_id, cs.production_date::date
    )
    SELECT
        pfm.date,
        pfm.production_line_id,
        pfm.production_company_id,
        pfm.material_id,
        mpl.line_json ->> 'material_name' AS material_name,
        round(pfm.budget_sqm, 1) AS budget_sqm,
        round(COALESCE(a.actual_sqm, 0), 1) AS actual_sqm,
        round(pfm.forecast_sqm, 1) AS forecast_sqm,
        pfm.param_json
    FROM log.production_forecast_material pfm
    JOIN relation.production_line pl
      ON pl.line_id = pfm.production_line_id
     AND pl.line_type = p_line_type
    LEFT JOIN mapping.material_production_line mpl
      ON mpl.material_id = pfm.material_id
     AND mpl.production_line_id = pfm.production_line_id
    LEFT JOIN actual a
      ON a.production_line_id = pfm.production_line_id
     AND a.material_id = pfm.material_id
     AND a.date = pfm.date
    WHERE pfm.date >= v_from
      AND pfm.date < v_from + p_days
    ORDER BY pfm.date, mpl.line_json ->> 'material_name';
END;
$$;

alter function get_production_forecast_material(unknown, unknown, unknown) owner to xfw3;

