create function search_phone(p_search_txt character varying) returns TABLE(code text, text text, description text, company_name text, company_type text, filejson jsonb)
	language plpgsql
as $$
BEGIN
    WITH all_phone_numbers AS (
        SELECT DISTINCT
            contact_id,
            CONCAT(COALESCE(contact.first_name || ' ', ''), COALESCE(contact.insertion || ' ', ''), contact.last_name) AS full_name,
            relation.clean_phone_number(phone) AS phone
        FROM relation.contact
        WHERE phone IS NOT NULL

        UNION

        SELECT DISTINCT
            contact_id,
            CONCAT(COALESCE(contact.first_name || ' ', ''), COALESCE(contact.insertion || ' ', ''), contact.last_name) AS full_name,
            relation.clean_phone_number(mobile) AS phone
        FROM relation.contact
        WHERE mobile IS NOT NULL

        UNION

        SELECT DISTINCT
            contact_id,
            CONCAT(COALESCE(contact.first_name || ' ', ''), COALESCE(contact.insertion || ' ', ''), contact.last_name) AS full_name,
            relation.clean_phone_number(company_phone) AS phone
        FROM relation.contact
        INNER JOIN relation.company
            ON contact.company_id = company.company_id
        WHERE company_phone IS NOT NULL
    )
    SELECT DISTINCT
        contact_id,
        CONCAT(phone, ' - ', full_name) AS text
    FROM all_phone_numbers
    WHERE phone <> ''
        AND full_name IS NOT NULL
        AND full_name <> ''
        AND phone LIKE relation.clean_phone_number(p_search_txt) || '%'
    ORDER BY text
    LIMIT 20;
END;
$$;

alter function search_phone(varchar) owner to xfw3;

