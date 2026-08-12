create function get_resource_capacity(p_model text, p_resource_uids text[] DEFAULT NULL::text[], p_until timestamp with time zone DEFAULT now()) returns TABLE(resource_uid text, resource_name text, profile_name text, material_names jsonb, data_json jsonb, capacity_sqm_per_day numeric, capacity_reserved_sqm numeric, capacity_left numeric)
	stable
	language plpgsql
as $$
BEGIN
    IF p_model IS NOT NULL AND array_length(p_resource_uids, 1) IS NULL THEN
        SELECT array_agg(res.resource_uid)
          INTO p_resource_uids
          FROM relation.resource        res
          JOIN relation.production_line  pl ON pl.line_id = res.line_id
         WHERE pl.model = p_model;
    END IF;

    RETURN QUERY
    WITH sheet_materials AS (
        SELECT
            trunc((spec->>'width')::numeric)::int   AS width,
            trunc((spec->>'height')::numeric)::int  AS height,
            coalesce((spec->>'sides')::int, 1)      AS sides,
            jsonb_agg(DISTINCT mpl.line_json->>'name') AS material_names,
            array_agg(DISTINCT mpl.material_id)        AS material_ids
        FROM mapping.material_production_line mpl
        JOIN relation.production_line pl
          ON pl.line_id = mpl.production_line_id
           , jsonb_array_elements(mpl.line_json->'specs') AS spec(value)
        WHERE pl.model = p_model
        GROUP BY width, height, sides
    ),
    state_capacity AS (
        SELECT
            s.resource_uid,
            s.capacity_sqm_per_day,
            s.capacity_reserved_sqm,
            s.capacity_left
        FROM log.get_resource_state_current(p_until, p_model) s
        WHERE s.resource_uid = ANY(p_resource_uids)
    )
    SELECT
        rip.resource_uid,
        r.resource_json->>'name' AS resource_name,
        rip.profile_name,
        sm.material_names,
        public.evaluate_many_nas(
            f.formula_json,
            (p.profile_json->'params')
                || jsonb_build_object(
                    'width',  sm.width,
                    'height', sm.height,
                    'sides',  sm.sides
                )
        ) AS data_json,
        sc.capacity_sqm_per_day,
        sc.capacity_reserved_sqm,
        sc.capacity_left
    FROM sheet_materials sm
    JOIN relation.resource_item_profile rip
      ON rip.resource_uid = ANY(p_resource_uids)
     AND rip.material_ids && sm.material_ids
    JOIN relation.resource r
      ON r.resource_uid = rip.resource_uid
    JOIN relation.profile p
      ON p.domain_id     = rip.domain_id
     AND p.profile_name  = rip.profile_name
     AND p.active        = true
    LEFT JOIN relation.formula f
      ON f.formula_id = p.formula_id
    LEFT JOIN state_capacity sc
      ON sc.resource_uid = rip.resource_uid
    WHERE 'production' = ANY(rip.profile_state)
    ORDER BY rip.resource_uid, rip.profile_name;
END;
$$;

alter function get_resource_capacity(text, text[], timestamp with time zone) owner to xfw3;

