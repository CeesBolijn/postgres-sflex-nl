create function mapping.get_resource_weight_history(p_resource_uids text[], p_until timestamp with time zone DEFAULT CURRENT_DATE, p_days integer DEFAULT 10) returns TABLE(batch_date date, resource_uid text, resource_name text, material_id integer, material_name text, amount bigint, weight numeric, sizes jsonb)
	stable
	language sql
as $$
    SELECT
        vc.batch_date,
        vc.resource_uid,
        vc.resource_name,
        vc.material_id,
        vc.material_name,
        SUM(vc.amount)::bigint AS amount,
        SUM(vc.weight) AS weight,
        jsonb_agg(jsonb_build_object(
            'width', vc.width,
            'height', vc.height,
            'sides', vc.sides,
            'amount', vc.amount,
            'weight', vc.weight
        ) ORDER BY vc.weight DESC) AS sizes
    FROM mapping.v_resource_capacity vc
    WHERE vc.resource_uid = ANY(p_resource_uids)
      AND vc.batch_date > (p_until - p_days * INTERVAL '1 day')
      AND vc.batch_date <= p_until
      AND vc.is_fastest_profile
    GROUP BY vc.batch_date, vc.resource_uid, vc.resource_name, vc.material_id, vc.material_name
    ORDER BY vc.batch_date, vc.resource_uid, weight DESC;
$$;

alter function mapping.get_resource_weight_history(text[], timestamp with time zone, integer) owner to xfw3;

