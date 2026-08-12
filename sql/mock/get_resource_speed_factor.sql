create function get_resource_speed_factor(p_material_id integer, p_resource_uid text) returns numeric
	stable
	language plpgsql
as $$
#variable_conflict use_column
DECLARE
    v_resource_uid      text := 'PRs29XOXqeuF';
    v_standard_duration numeric;
    v_resource_duration numeric;
BEGIN
    v_standard_duration := mock.get_material_resource_duration(p_material_id, v_resource_uid);
    v_resource_duration := mock.get_material_resource_duration(p_material_id, p_resource_uid);

    IF v_standard_duration IS NULL OR v_standard_duration = 0
       OR v_resource_duration IS NULL OR v_resource_duration = 0 THEN
        RETURN 1;
    END IF;

    RETURN round(v_standard_duration / v_resource_duration, 3);
END;
$$;

alter function get_resource_speed_factor(integer, text) owner to xfw3;

