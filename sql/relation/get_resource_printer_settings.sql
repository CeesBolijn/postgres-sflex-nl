-- Returns all print modes per resource, optionally filtered by resource_uid
CREATE OR REPLACE FUNCTION relation.get_resource_printer_settings(
    p_resource_uid text DEFAULT NULL
)
RETURNS TABLE (
    resource_uid          text,
    resource_name         text,
    mode                  text,
    horizontal_resolution int,
    vertical_resolution   int,
    print_passes          int,
    passoverlap_level     int,
    print_mode            text,
    print_speed_sqm       numeric,
    description           text
)
LANGUAGE plpgsql
AS $$
#variable_conflict use_column
BEGIN
    RETURN QUERY
    SELECT
        r.resource_uid,
        r.resource_name,
        el->>'mode',
        (el->>'horizontal_resolution')::int,
        (el->>'vertical_resolution')::int,
        (el->>'print_passes')::int,
        (el->>'passoverlap_level')::int,
        el->>'print_mode',
        (el->'params'->>'print_speed_sqm')::numeric,
        el->>'description'
    FROM relation.resource r
    JOIN relation.equipment e
        ON (r.resource_json->>'equipment_id')::int = e.equipment_id,
        jsonb_array_elements(e.equipment_json->'data'->'modi') AS el
    WHERE p_resource_uid IS NULL OR r.resource_uid = p_resource_uid
    ORDER BY r.resource_name,
        (el->>'horizontal_resolution')::int,
        (el->>'vertical_resolution')::int,
        (el->>'print_passes')::int,
        (el->>'passoverlap_level')::int;
END;
$$;

ALTER FUNCTION relation.get_resource_printer_settings(text) OWNER TO xfw3;

-- Usage:
-- SELECT * FROM relation.get_resource_printer_settings();               -- all
-- SELECT * FROM relation.get_resource_printer_settings('Kudu-240183');  -- one printer
--
-- Note: cutters/coaters have a different modi structure and fall out of this
-- function naturally (empty join). They should get their own
-- get_resource_cutter_settings later, per the data_groups pattern.
