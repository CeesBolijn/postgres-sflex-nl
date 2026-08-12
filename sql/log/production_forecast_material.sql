create materialized view production_forecast_material as
	WITH material_share AS (
         SELECT mpl.production_line_id,
            cs.material_id,
            sum(cs.sqm) / NULLIF(sum(sum(cs.sqm)) OVER (PARTITION BY mpl.production_line_id), 0::numeric) AS line_fraction
           FROM mapping.component_specs cs
             JOIN mapping.material_production_line mpl ON cs.material_id = mpl.material_id
          WHERE cs.production_date >= (now() - '42 days'::interval) AND cs.production_date <= now() AND cs.sqm IS NOT NULL
          GROUP BY mpl.production_line_id, cs.material_id
        ), material_standard AS (
         SELECT DISTINCT ms_1.material_id,
            mock.get_material_standard_duration_per_sqm(ms_1.material_id) AS standard_duration_per_sqm
           FROM material_share ms_1
        )
 SELECT f.date,
    f.production_line_id,
    f.production_company_id,
    ms.material_id,
    f.budget_m2_last_6_weeks * ms.line_fraction AS budget_sqm_last_6_weeks,
    f.actual_m2_last_6_weeks * ms.line_fraction AS actual_sqm_last_6_weeks,
    f.budget_m2_last_6_weeks * ms.line_fraction / 30::numeric AS budget_sqm,
    f.actual_m2_last_6_weeks * ms.line_fraction / 30::numeric AS actual_sqm,
    f.m2_forecast * ms.line_fraction AS forecast_sqm,
    jsonb_build_object('budget_production_impact', round(f.budget_m2_last_6_weeks * ms.line_fraction / 30::numeric * mst.standard_duration_per_sqm, 3), 'actual_production_impact', round(f.actual_m2_last_6_weeks * ms.line_fraction / 30::numeric * mst.standard_duration_per_sqm, 3), 'forecast_production_impact', round(f.m2_forecast * ms.line_fraction * mst.standard_duration_per_sqm, 3)) AS param_json
   FROM log.production_forecast f
     JOIN material_share ms ON ms.production_line_id = f.production_line_id
     LEFT JOIN material_standard mst ON mst.material_id = ms.material_id;

alter materialized view production_forecast_material owner to xfw3;

create unique index uq_production_forecast_material
	on production_forecast_material (date, production_line_id, production_company_id, material_id);

