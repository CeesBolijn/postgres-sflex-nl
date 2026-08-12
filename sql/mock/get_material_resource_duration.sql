create function get_material_resource_duration(p_material_id integer, p_resource_uid text) returns numeric
	stable
	language plpgsql
as $$
#variable_conflict use_column
DECLARE
    v_width  numeric;
    v_height numeric;
    v_sides  integer;
    v_duration numeric;
BEGIN
    SELECT s.width, s.height, s.sides
      INTO v_width, v_height, v_sides
    FROM mock.get_material_line_specs(p_material_id) s;

    IF v_width IS NULL OR v_height IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT (candidate.data_json ->> 'duration')::numeric
      INTO v_duration
    FROM (
        SELECT
            public.evaluate_many_nas(
                f.formula_json,
                (p.profile_json -> 'params')
                    || jsonb_build_object('width', v_width, 'height', v_height, 'sides', v_sides)
            ) AS data_json
        FROM relation.resource_item_profile rip
        JOIN relation.profile p
          ON p.domain_id    = rip.domain_id
         AND p.profile_name = rip.profile_name
         AND p.active       = true
        LEFT JOIN relation.formula f
               ON f.formula_id = p.formula_id
        WHERE rip.resource_uid  = p_resource_uid
          AND p_material_id     = ANY (rip.material_ids)
          AND 'production'      = ANY (rip.profile_state)
    ) candidate
    ORDER BY (candidate.data_json ->> 'panels_hour')::numeric DESC NULLS LAST
    LIMIT 1;

    RETURN v_duration;
END;
$$;

alter function get_material_resource_duration(integer, text) owner to xfw3;

