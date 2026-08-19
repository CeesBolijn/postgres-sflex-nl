create function get_blocks(p_path character varying, p_user_domain_id integer, p_user_company_id integer, p_roles jsonb) returns TABLE(status_code integer, company_id integer, page_id integer, block_id integer, block_json jsonb, sort_order integer, environment jsonb, ml_nav_json jsonb, languages jsonb, data_groups jsonb, navs jsonb, css_variables jsonb)
	language plpgsql
as $$
DECLARE
    v_custom_styling BOOLEAN;
    v_page_id INTEGER := NULL;
    v_block_id INTEGER;
    v_company_ids TEXT;
BEGIN
    -- Get custom styling setting
    SELECT (d.website_config->>'custom_styling')::boolean 
    INTO v_custom_styling
    FROM site.domain d
    WHERE d.domain_id = p_user_domain_id;

    -- Find page by path
    IF p_path <> '' AND p_path IS NOT NULL THEN
        SELECT p.page_id INTO v_page_id
        FROM site.page p
        INNER JOIN site.domain_page dp ON p.page_id = dp.page_id
        WHERE p.path::text LIKE '%"' || p_path || '"%'
          AND dp.domain_id = p_user_domain_id
        LIMIT 1;
    END IF;

    -- Handle 404 - page not found
    IF v_page_id IS NULL THEN
        SELECT (d.website_config->>'not_found_page_id')::integer 
        INTO v_page_id
        FROM site.domain d
        WHERE d.domain_id = p_user_domain_id;

        RETURN QUERY
        SELECT
            404 AS status_code,
            NULL::integer AS company_id,
            pg.page_id,
            b.block_id,
            b.block_json,
            pb.sort_order,
            pg.environment,
            pg.path AS ml_nav_json,
            b.languages,
            site.get_page_data_groups(pg.page_id) AS data_groups,
            site.get_page_navs(pg.page_id, p_user_domain_id) AS navs,
            NULL::jsonb AS css_variables
        FROM site.block b
        INNER JOIN site.page_block pb ON b.block_id = pb.block_id
        INNER JOIN site.page pg ON pb.page_id = pg.page_id
        WHERE pg.page_id = COALESCE(v_page_id, 447)
        ORDER BY pb.sort_order;
        
        RETURN;
    END IF;

    -- Create temporary table for blocks
    DROP TABLE IF EXISTS temp_blocks;
    CREATE TEMP TABLE temp_blocks (
        block_id INTEGER,
        company_id INTEGER
    );

    -- Populate blocks based on company IDs
    FOR v_block_id, v_company_ids IN
        SELECT b.block_id, b.company_ids::text
        FROM site.block b
        INNER JOIN site.page_block pb ON b.block_id = pb.block_id
        WHERE pb.page_id = v_page_id
          AND b.hidden = false
          AND (
          -- Both are empty arrays
          (jsonb_array_length(b.roles) = 0 AND jsonb_array_length(p_roles) = 0)
          -- OR b.roles contains any element from p_roles
          OR b.roles ?| ARRAY(SELECT jsonb_array_elements_text(p_roles))
      )
    LOOP
        IF v_company_ids = '[]' THEN
            INSERT INTO temp_blocks (block_id, company_id)
            VALUES (v_block_id, NULL);
        ELSE
            INSERT INTO temp_blocks (block_id, company_id)
            SELECT v_block_id, (value::text)::integer
            FROM jsonb_array_elements_text(v_company_ids::jsonb);
        END IF;
    END LOOP;

    -- Return blocks if found
    IF EXISTS (SELECT 1 FROM temp_blocks) THEN
        RETURN QUERY
        SELECT
            200 AS status_code,
            bs.company_id,
            pg.page_id,
            b.block_id,
            b.block_json,
            pb.sort_order,
            pg.environment,
            pg.path AS ml_nav_json,
            b.languages,
            site.get_page_data_groups(v_page_id) AS data_groups,
            site.get_page_navs(v_page_id, p_user_domain_id) AS navs,
            CASE 
                WHEN v_custom_styling THEN 
                    (SELECT c.config->'css_variables'
                     FROM relation.company c
                     WHERE c.company_id IN (
                         SELECT (value::text)::integer 
                         FROM jsonb_array_elements_text(b.block_json->'suppliers')
                     )
                     LIMIT 1)
                ELSE '{}'::jsonb
            END AS css_variables
        FROM temp_blocks bs
        INNER JOIN site.block b ON bs.block_id = b.block_id
        INNER JOIN site.page_block pb ON b.block_id = pb.block_id
        INNER JOIN site.page pg ON pb.page_id = pg.page_id
        WHERE pg.page_id = v_page_id
           AND (
            bs.company_id IS NULL
                OR bs.company_id = p_user_company_id
                OR (
                bs.company_id = relation.get_root_parent_company_id(p_user_company_id, p_user_domain_id)
                    AND NOT EXISTS(SELECT 1
                                   FROM temp_blocks tb
                                   WHERE tb.company_id = p_user_company_id)
                )
            )
        ORDER BY pb.sort_order;
        
        DROP TABLE IF EXISTS temp_blocks;
        RETURN;
    END IF;

    -- Handle 403 - no permission
    SELECT (d.website_config->>'no_permission_page_id')::integer 
    INTO v_page_id
    FROM site.domain d
    WHERE d.domain_id = p_user_domain_id;

    RETURN QUERY
    SELECT
        403 AS status_code,
        NULL::integer AS company_id,
        pg.page_id,
        b.block_id,
        b.block_json,
        pb.sort_order,
        pg.environment,
        pg.path AS ml_nav_json,
        b.languages,
        site.get_page_data_groups(pg.page_id) AS data_groups,
        site.get_page_navs(pg.page_id, p_user_domain_id) AS navs,
        NULL::jsonb AS css_variables
    FROM site.block b
    INNER JOIN site.page_block pb ON b.block_id = pb.block_id
    INNER JOIN site.page pg ON pb.page_id = pg.page_id
    WHERE pg.page_id = COALESCE(v_page_id, 656)
    ORDER BY pb.sort_order;

    DROP TABLE IF EXISTS temp_blocks;
END;
$$;

alter function get_blocks(varchar, integer, integer, jsonb) owner to xfw3;

