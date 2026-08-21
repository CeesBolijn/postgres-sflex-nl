create function mapping.get_material_ids_by_production_orderline(p_production_orderline_id integer) returns integer[]
	stable
	language sql
as $$
    SELECT array_agg(DISTINCT m.material_id)
    FROM (
        SELECT cs.material_id
        FROM mapping.component_specs cs
        WHERE cs.production_orderline_id = p_production_orderline_id
          AND cs.material_id IS NOT NULL
        UNION
        SELECT soo.material_id
        FROM mapping.sales_orderline_option soo
        JOIN mapping.component_specs cs
            ON cs.sales_orderline_id = soo.sales_orderline_id
        WHERE cs.production_orderline_id = p_production_orderline_id
          AND soo.material_id IS NOT NULL
        ORDER BY 1
    ) m;
$$;

alter function mapping.get_material_ids_by_production_orderline(integer) owner to xfw3;

