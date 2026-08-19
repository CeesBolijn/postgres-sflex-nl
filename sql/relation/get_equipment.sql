create function get_equipment() returns TABLE(equipment_id integer)
	language plpgsql
as $$
BEGIN
    RETURN QUERY
    SELECT
        equipment.equipment_id
    FROM relation.equipment;
END;
$$;

alter function get_equipment() owner to xfw3;

