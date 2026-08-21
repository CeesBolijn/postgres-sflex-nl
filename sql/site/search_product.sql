create function site.search_product(p_search_txt character varying) returns TABLE(code text, text text, description text, company_name text, company_type text, filejson jsonb)
	language plpgsql
as $$
BEGIN
    RETURN QUERY SELECT
        product.code,
        COALESCE(meta_json->>'text', product_json->'block'->>'title') AS text,
        'Heel mooi.' AS description,
        CASE
            WHEN product.code LIKE 'PP100.%' THEN 'Probo'
            WHEN product.code LIKE 'efka.%' THEN 'Efka'
            WHEN product.code LIKE 'cs15216.%' THEN 'CS'
            ELSE 'Overig'
        END AS company_name,
        'Print Provider' AS company_type,
        jsonb_build_object(
            'imgAndThumbs', jsonb_build_array(
                jsonb_build_object(
                    'thumbFileName', '24-00123-01- NE3a4uvsm87_Orajet 3651 RA - wit - glans_152_ORA210GL_100FC',
                    'thumbUrl', COALESCE(meta_json->>'imageUrl', 'https://xfw3.b-cdn.net/ui/noimg.svg')
                )
            )
        ) AS file_json
    FROM configurator.product
    WHERE COALESCE(meta_json->>'text', product_json->'block'->>'title') ILIKE '%' || p_search_txt || '%'
    ORDER BY text
    LIMIT 20;
END;
$$;

alter function site.search_product(varchar) owner to xfw3;

