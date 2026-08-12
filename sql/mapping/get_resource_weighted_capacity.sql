create function get_resource_weighted_capacity(p_resource_uids text[] DEFAULT NULL::text[], p_from date DEFAULT (CURRENT_DATE - 30), p_until date DEFAULT CURRENT_DATE, p_hours_per_day numeric DEFAULT 18, p_oee numeric DEFAULT 1, p_nesting_eff numeric DEFAULT 1) returns TABLE(resource_uid text, resource_name text, width integer, height integer, sides integer, material_id integer, material_name text, profile_name text, total_amount bigint, weight numeric, panels_hour numeric, panels_per_day numeric, capacity_sqm_per_day numeric, param_from date, param_until date, param_hours_per_day numeric, param_oee numeric, param_nesting_eff numeric)
	stable
	language sql
as $$
    WITH period_amounts AS (
        SELECT
            vc.resource_uid,
            vc.resource_name,
            vc.width,
            vc.height,
            vc.sides,
            vc.material_id,
            vc.material_name,
            vc.profile_name,
            (vc.data_json ->> 'panels_hour')::numeric          AS panels_hour,
            SUM(vc.amount)                                     AS total_amount
        FROM mapping.v_resource_capacity vc
        WHERE (p_resource_uids IS NULL OR vc.resource_uid = ANY(p_resource_uids))
          AND vc.batch_date >= p_from
          AND vc.batch_date <  p_until
          AND vc.is_fastest_profile
        GROUP BY
            vc.resource_uid, vc.resource_name,
            vc.width, vc.height, vc.sides,
            vc.material_id, vc.material_name,
            vc.profile_name,
            (vc.data_json ->> 'panels_hour')::numeric
    ),
    period_weight AS (
        SELECT
            pa.*,
            ROUND(
                pa.total_amount::numeric
                / SUM(pa.total_amount) OVER (PARTITION BY pa.resource_uid),
                4
            )                                                  AS weight
        FROM period_amounts pa
    ),
    totals AS (
        SELECT
            pw.resource_uid,
            SUM(pw.weight / NULLIF(pw.panels_hour, 0))        AS weighted_hours_per_panel
        FROM period_weight pw
        GROUP BY pw.resource_uid
    )
    SELECT
        pw.resource_uid,
        pw.resource_name,
        pw.width,
        pw.height,
        pw.sides,
        pw.material_id,
        pw.material_name,
        pw.profile_name,
        pw.total_amount,
        pw.weight,
        pw.panels_hour,
        ROUND(
            CASE WHEN t.weighted_hours_per_panel > 0
                THEN p_hours_per_day * p_oee / t.weighted_hours_per_panel * pw.weight
                ELSE 0
            END,
            2
        )                                                      AS panels_per_day,
        ROUND(
            CASE WHEN t.weighted_hours_per_panel > 0
                THEN p_hours_per_day * p_oee / t.weighted_hours_per_panel
                     * pw.weight * pw.width * pw.height / 10000.0
                     * p_nesting_eff
                ELSE 0
            END,
            4
        )                                                      AS capacity_sqm_per_day,
        p_from                                                 AS param_from,
        p_until                                                AS param_until,
        p_hours_per_day                                        AS param_hours_per_day,
        p_oee                                                  AS param_oee,
        p_nesting_eff                                          AS param_nesting_eff
    FROM period_weight pw
    JOIN totals t ON t.resource_uid = pw.resource_uid
    ORDER BY pw.resource_uid, pw.weight DESC;
$$;

alter function get_resource_weighted_capacity(text[], date, date, numeric, numeric, numeric) owner to xfw3;

