create function search_contact(p_user_domain_id integer, p_search_txt character varying DEFAULT NULL::character varying) returns TABLE(_contact_id integer, text character varying)
	language plpgsql
as $$
BEGIN
    RETURN QUERY
    SELECT
        contact.contact_id                                                                          AS _contact_id,
        CONCAT(first_name, COALESCE(' ' || insertion || ' ', ' '), last_name) :: VARCHAR            AS text
    FROM relation.contact
    INNER JOIN relation.company_domain
        ON contact.company_id = company_domain.company_id
        AND company_domain.domain_id IN (
            SELECT p_user_domain_id
--          UNION
--          SELECT sub_domain_id
--          FROM site.domain_domain
--          WHERE domain_id = p_user_domain_id
        )
    WHERE CONCAT(first_name, COALESCE(' ' || insertion || ' ', ' '), last_name) LIKE '%' || COALESCE(p_search_txt, '') || '%'
    ORDER BY text
    LIMIT 20;
END;
$$;

alter function search_contact(integer, varchar) owner to xfw3;

