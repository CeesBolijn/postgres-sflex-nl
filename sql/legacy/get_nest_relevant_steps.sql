create function legacy.get_nest_relevant_steps(p_nest_name text) returns TABLE(step text)
	language sql
as $$
    SELECT 'rip' step;
--     UNION
--     SELECT DISTINCT r.step
--     FROM legacy.single_product sp
--     JOIN legacy.nest n ON sp.nest_id = n.nest_id
--     JOIN mock.material_print_schedule mpa
--         ON mpa.material_ids = mapping.get_material_ids_by_production_orderline(
--             p_production_orderline_id := sp.production_orderline_id
--         )::int[]
--     JOIN LATERAL jsonb_array_elements_text(mpa.resource_uids) AS ru(resource_uid) ON true
--     JOIN relation.resource r
--         ON r.resource_uid = ru.resource_uid
--     WHERE n.nest_name = p_nest_name;
$$;

alter function legacy.get_nest_relevant_steps(text) owner to xfw3;

