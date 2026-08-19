create function search_company_route(p_search_txt character varying) returns TABLE(text character varying, _gmap character varying)
	language plpgsql
as $$
BEGIN
    RETURN QUERY
    WITH parts AS (
        SELECT
            part,
            SUBSTRING(part, 1, 1) AS prefix,
            ROW_NUMBER() OVER (ORDER BY ordinality) AS part_index,
            CASE
                WHEN POSITION(':' IN part) > 0
                THEN SUBSTRING(part, 2, POSITION(':' IN part) - 2)
                ELSE SUBSTRING(part, 2, LENGTH(part) - 1)
            END AS company_part,
            CASE
                WHEN POSITION(':' IN part) > 0
                THEN SUBSTRING(part, POSITION(':' IN part) + 1, LENGTH(part) - POSITION(':' IN part))
                ELSE NULL
            END AS place_part
        FROM UNNEST(string_to_array(p_search_txt, '-')) WITH ORDINALITY AS t(part, ordinality)
    ),
    lookup_results_unfiltered AS (
        SELECT
            parts.*,
            company.company_name,
            address.place,
            ROW_NUMBER() OVER (PARTITION BY parts.part_index ORDER BY address.place DESC) AS row_num
        FROM parts
        LEFT JOIN relation.company
            ON company.company_name LIKE parts.company_part || '%'
        LEFT JOIN relation.address
            ON address.company_id = company.company_id
            AND (parts.place_part IS NULL OR address.place LIKE parts.place_part || '%')
        WHERE parts.part_index < (SELECT MAX(part_index) FROM parts)
    ),
    lookup_results AS (
        SELECT *
        FROM lookup_results_unfiltered
        WHERE row_num = 1
    ),
    lookup_results_joined AS (
        SELECT
            STRING_AGG(
                CASE
                    WHEN prefix = '.'
                    THEN '.' || CASE
                        WHEN place IS NOT NULL AND place != ''
                        THEN company_name || ':' || place
                        ELSE company_name
                    END
                    ELSE part
                END,
                '-' ORDER BY part_index
            ) AS agg_text,
            STRING_AGG(
                COALESCE(place, part, ' '),
                '-' ORDER BY part_index
            ) AS agg_location
        FROM lookup_results
    ),
    lookup_result_last AS (
        SELECT
            CASE
                WHEN parts.prefix = '.'
                THEN '.' || CASE
                    WHEN address.place IS NOT NULL AND address.place != ''
                    THEN company.company_name || ':' || address.place
                    ELSE company.company_name
                END
                ELSE parts.part
            END AS last_text,
            COALESCE(address.place, parts.part, ' ') AS last_location
        FROM parts
        INNER JOIN relation.company
            ON company.company_name LIKE parts.company_part || '%'
        INNER JOIN relation.address
            ON address.company_id = company.company_id
        WHERE parts.part_index = (SELECT MAX(part_index) FROM parts)
            AND TRIM(address.place) != ''
            AND address.place IS NOT NULL
            AND parts.prefix = '.'
            AND (parts.place_part IS NULL OR address.place LIKE parts.place_part || '%')
        ORDER BY address.place
        LIMIT 10
    )
    SELECT
        CASE
            WHEN EXISTS (SELECT 1 FROM lookup_results_joined WHERE agg_text != '')
            THEN (SELECT agg_text FROM lookup_results_joined) || '-' || lrl.last_text
            ELSE lrl.last_text
        END :: VARCHAR AS text,
        CASE
            WHEN EXISTS (SELECT 1 FROM lookup_results_joined WHERE agg_location != '')
            THEN (SELECT agg_location FROM lookup_results_joined) || '-' || lrl.last_location
            ELSE lrl.last_location
        END :: VARCHAR AS _gmap
    FROM lookup_result_last lrl;
END;
$$;

alter function search_company_route(varchar) owner to xfw3;

