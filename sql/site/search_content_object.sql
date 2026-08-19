create function search_content_object(p_search_txt character varying, p_roles jsonb, p_user_domain_id integer) returns TABLE(path character varying, block_json text, sort_order integer, hidden integer, page_id integer, block_id integer, action_id integer)
	language plpgsql
as $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT
        ((page.path::jsonb ->> 0) || '?searchTxt=' || p_search_txt) :: VARCHAR   AS path,
        block.block_json                                                           AS block_json,
        page_block.sort_order                                                      AS sort_order,
        1                                                                          AS hidden,
        page.page_id                                                               AS page_id,
        block.block_id                                                             AS block_id,
        NULL :: INT                                                                AS action_id
    FROM site.block
    INNER JOIN site.page_block
        ON block.block_id = page_block.block_id
    INNER JOIN site.page
        ON page_block.page_id = page.page_id
    INNER JOIN site.domain_page
        ON page.page_id = domain_page.page_id
    WHERE block.block_json LIKE '%' || p_search_txt || '%'
        AND block.block_json NOT LIKE '%nav%'
        AND block.hidden = 0
        AND (
            (jsonb_array_length(block.roles) = 0 AND jsonb_array_length(p_roles) = 0)
            OR block.roles ?| ARRAY(SELECT jsonb_array_elements_text(p_roles))
        )
        AND domain_page.domain_id = p_user_domain_id;
END;
$$;

alter function search_content_object(varchar, jsonb, integer) owner to xfw3;

