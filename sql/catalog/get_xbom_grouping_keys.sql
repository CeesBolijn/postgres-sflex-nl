create function catalog.get_xbom_grouping_keys(option_codes text[]) returns TABLE(scope text, grouping_key text[])
	stable
	parallel safe
	language sql
as $$
    WITH input AS (
        SELECT DISTINCT c.option_code
        FROM unnest(option_codes) AS c(option_code)
    ),
    base AS (
        -- incoming codes that exist in the library, with their own combination spec
        SELECT lo.option_id,
               lo.option_code,
               lo.option_json -> 'combine_with' AS combine_with,
               CASE WHEN jsonb_typeof(lo.option_json -> 'combine_with') = 'array'
                    THEN jsonb_array_length(lo.option_json -> 'combine_with')
                    ELSE 0
               END AS axis_total
        FROM catalog.library_option lo
        JOIN input i ON i.option_code = lo.option_code
        WHERE lo.version_status = 'active'
    ),
    member AS (
        -- axis members that are present in the incoming set, numbered from 0 per axis
        SELECT b.option_id,
               a.axis_index,
               c.option_code,
               row_number() OVER (PARTITION BY b.option_id, a.axis_index
                                  ORDER BY lo.sort_order, c.option_code) - 1 AS member_index
        FROM base b
        CROSS JOIN LATERAL jsonb_array_elements(b.combine_with)
                           WITH ORDINALITY AS a(codes, axis_index)
        CROSS JOIN LATERAL jsonb_array_elements_text(a.codes) AS c(option_code)
        JOIN input i ON i.option_code = c.option_code
        JOIN catalog.library_option lo ON lo.option_code = c.option_code
                                      AND lo.version_status = 'active'
        WHERE b.axis_total > 0
    ),
    dim AS (
        -- number of present candidates per axis
        SELECT option_id, axis_index, count(*)::bigint AS size
        FROM member
        GROUP BY option_id, axis_index
    ),
    complete AS (
        -- a combined code can only be formed when every declared axis is covered
        SELECT b.option_id
        FROM base b
        JOIN dim d ON d.option_id = b.option_id
        WHERE b.axis_total > 0
        GROUP BY b.option_id, b.axis_total
        HAVING count(*) = b.axis_total
    ),
    radix AS (
        -- multiplier = product of the sizes of all later axes (last axis varies fastest)
        SELECT d.option_id,
               d.axis_index,
               d.size,
               round(exp(coalesce(sum(ln(d.size::numeric)) OVER (PARTITION BY d.option_id
                                                                 ORDER BY d.axis_index DESC
                                                                 ROWS BETWEEN UNBOUNDED PRECEDING
                                                                          AND 1 PRECEDING), 0)))::bigint AS multiplier
        FROM dim d
        JOIN complete c ON c.option_id = d.option_id
    ),
    total AS (
        -- total number of combinations per base option
        SELECT d.option_id,
               round(exp(sum(ln(d.size::numeric))))::bigint AS combo_count
        FROM dim d
        JOIN complete c ON c.option_id = d.option_id
        GROUP BY d.option_id
    ),
    picked AS (
        -- decode every combination index into exactly one member per axis
        SELECT t.option_id,
               i.combo_index,
               r.axis_index,
               m.option_code
        FROM total t
        CROSS JOIN LATERAL generate_series(0, t.combo_count - 1) AS i(combo_index)
        JOIN radix  r ON r.option_id = t.option_id
        JOIN member m ON m.option_id    = t.option_id
                     AND m.axis_index   = r.axis_index
                     AND m.member_index = (i.combo_index / r.multiplier) % r.size
    ),
    candidate AS (
        -- options without a combination spec resolve to their own code
        SELECT b.option_code
        FROM base b
        WHERE b.axis_total = 0

        UNION

        -- base option combined with one present member of every axis, in axis order
        SELECT b.option_code || ';' || string_agg(p.option_code, ';' ORDER BY p.axis_index)
        FROM picked p
        JOIN base b ON b.option_id = p.option_id
        GROUP BY b.option_code, p.combo_index
    )
    -- keep only the codes that actually drive an xbom line; per scope those
    -- codes together form the grouping key for that scope
    SELECT x.scope,
           array_agg(DISTINCT c.option_code ORDER BY c.option_code)
    FROM candidate c
    JOIN catalog.xbom x ON x.option_code = c.option_code
    WHERE x.status = 'active'
    GROUP BY x.scope;
$$;

alter function catalog.get_xbom_grouping_keys(text[]) owner to xfw3;

