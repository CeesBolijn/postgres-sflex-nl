create function site.get_address_entry() returns TABLE(country_code character, postcode character varying, city text, street text, house_number integer, house_number_suffix character varying, house_letter character, unit character varying, po_box character varying)
	language sql
as $$
    SELECT
        NULL::CHAR(2),
        NULL::VARCHAR(10),
        NULL::TEXT,
        NULL::TEXT,
        NULL::INT,
        NULL::VARCHAR(10),
        NULL::CHAR(1),
        NULL::VARCHAR(20),
        NULL::VARCHAR(20);
$$;

alter function site.get_address_entry() owner to xfw3;

