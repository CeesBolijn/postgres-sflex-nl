create function site.search_company(p_user_domain_id integer, p_search_txt character varying DEFAULT NULL::character varying) returns TABLE(company_id integer, text character varying)
	language plpgsql
as $$
BEGIN
    RETURN QUERY
    SELECT
        company.company_id                                                          AS company_id,
        CONCAT(relation_code, ' - ', company_name) :: VARCHAR                      AS text
    FROM relation.company
    INNER JOIN relation.company_domain
        ON company.company_id = company_domain.company_id
        AND company_domain.domain_id = p_user_domain_id
    WHERE company.company_name LIKE '%' || COALESCE(p_search_txt, '') || '%'
    ORDER BY company.company_name
    LIMIT 20;
END;
$$;

alter function site.search_company(integer, varchar) owner to xfw3;

