create function search_company_location(p_search_txt character varying) returns TABLE(text character varying, _gmap character varying)
	language plpgsql
as $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT
        company.company_name :: VARCHAR                              AS text,
        CONCAT(address.place, ' ', address.country) :: VARCHAR      AS _gmap
    FROM relation.company
    INNER JOIN relation.company_address
        ON company.company_id = company_address.company_id
    INNER JOIN relation.address
        ON company_address.address_id = address.address_id
    WHERE company.company_name LIKE p_search_txt || '%'
    ORDER BY text
    LIMIT 10;
END;
$$;

alter function search_company_location(varchar) owner to xfw3;

