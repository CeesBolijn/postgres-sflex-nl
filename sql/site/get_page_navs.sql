create function site.get_page_navs(p_page_id integer, p_user_company_id integer) returns jsonb
	language plpgsql
as $$
DECLARE
    v_navs TEXT;
BEGIN
    WITH navs AS (
        SELECT DISTINCT
            col_data->'nav_json'->>'nav' AS nav
        FROM site.page_block pb
        INNER JOIN site.block b ON pb.block_id = b.block_id
        CROSS JOIN LATERAL jsonb_array_elements(
            COALESCE(b.block_json->'cols', '[]'::jsonb)
        ) AS cols_data
        CROSS JOIN LATERAL jsonb_array_elements(
            COALESCE(cols_data->'col', '[]'::jsonb)
        ) AS col_data
        WHERE pb.page_id = p_page_id
          AND col_data->'nav_json'->>'nav' IS NOT NULL
    ),
    personalized_navs AS (
        SELECT
            n.nav,
            n.nav_json,
            n.company_ids,
            CASE
                WHEN EXISTS (
                    SELECT 1
                    FROM site.nav inner_nav
                    INNER JOIN navs inner_navs ON inner_nav.nav = inner_navs.nav
                    CROSS JOIN LATERAL jsonb_array_elements_text(
                        COALESCE(inner_nav.company_ids, '[]'::jsonb)
                    ) AS company_id
                    WHERE company_id::integer = p_user_company_id
                      AND inner_nav.nav = n.nav
                ) THEN 1
                ELSE 0
            END AS has_access
        FROM site.nav n
        INNER JOIN navs ON n.nav = navs.nav
        WHERE n.company_ids = '[]'::jsonb
           OR p_user_company_id IN (
               SELECT (value::text)::integer
               FROM jsonb_array_elements_text(n.company_ids)
           )
    )
    SELECT json_agg(
        json_build_object(
            'nav', nav,
            'nav_json', nav_json
        )
    )
    INTO v_navs
    FROM personalized_navs
    WHERE (has_access = 0 AND company_ids = '[]'::jsonb)
       OR (has_access = 1 AND company_ids <> '[]'::jsonb);

    RETURN v_navs;
END;
$$;

alter function site.get_page_navs(integer, integer) owner to xfw3;

