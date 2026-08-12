create function get_material_standard_duration_per_sqm(p_material_id integer) returns numeric
	stable
	language plpgsql
as $$
#variable_conflict use_column
DECLARE
    v_resource_uid  text := 'PRs29XOXqeuF';
    v_duration      numeric;
    v_width         numeric;
    v_height        numeric;
    v_sides         integer;
    v_panel_sqm     numeric;
BEGIN
    SELECT s.width, s.height, s.sides
      INTO v_width, v_height, v_sides
    FROM mock.get_material_line_specs(p_material_id) s;

    v_duration := mock.get_material_resource_duration(p_material_id, v_resource_uid);

    -- width/height in cm -> m² (100 cm/m * 100 cm/m)
    v_panel_sqm := (v_width * v_height) / 10000.0;

    IF v_duration IS NULL OR v_panel_sqm IS NULL OR v_panel_sqm = 0 THEN
        RETURN NULL;
    END IF;

    RETURN round(v_duration / v_panel_sqm, 3);
END;
$$;

alter function get_material_standard_duration_per_sqm(integer) owner to xfw3;

