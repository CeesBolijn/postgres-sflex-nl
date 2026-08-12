create function crud_xbom() returns TABLE(option_code text)
	language plpgsql
as $$
#variable_conflict use_column
BEGIN
    RETURN QUERY
    WITH base AS (
        -- every active option in the collection, with its own combination spec
        SELECT los.collection_id,
               los.option_set,
               lo.option_id,
               lo.option_code,
               lo.option_json -> 'combine_with' AS combine_with
        FROM   catalog.library_option_set los
        JOIN   catalog.library_option lo ON lo.option_set_id = los.option_set_id
                                        AND lo.version_status = 'active'
        WHERE los.status = 'active'
    ),
    axis AS (
        -- one row per allowed option_code per axis; the axis members are listed explicitly
        SELECT b.collection_id,
               b.option_id,
               a.axis_index,
               c.option_code
        FROM   base b
        CROSS JOIN LATERAL jsonb_array_elements(b.combine_with)
                           WITH ORDINALITY AS a(codes, axis_index)
        CROSS JOIN LATERAL jsonb_array_elements_text(a.codes) AS c(option_code)
        WHERE  jsonb_typeof(b.combine_with) = 'array'
    ),
    member AS (
        -- keep only codes that exist and are active, numbered from 0 per axis
        SELECT a.option_id,
               a.axis_index,
               a.option_code,
               row_number() OVER (PARTITION BY a.option_id, a.axis_index
                                  ORDER BY lo.sort_order, a.option_code) - 1 AS member_index
        FROM   axis a
        JOIN   catalog.library_option_set los ON los.collection_id = a.collection_id
                                             AND los.status = 'active'
        JOIN   catalog.library_option lo ON lo.option_set_id = los.option_set_id
                                        AND lo.option_code   = a.option_code
                                        AND lo.version_status = 'active'
    ),
    dim AS (
        -- number of candidates per axis
        SELECT option_id, axis_index, count(*)::bigint AS size
        FROM   member
        GROUP  BY option_id, axis_index
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
        FROM   dim d
    ),
    total AS (
        -- total number of combinations per base option
        SELECT option_id,
               round(exp(sum(ln(size::numeric))))::bigint AS combo_count
        FROM   dim
        GROUP  BY option_id
    ),
    picked AS (
        -- decode every combination index into exactly one member per axis
        SELECT t.option_id,
               i.combo_index,
               r.axis_index,
               m.option_code
        FROM   total t
        CROSS JOIN LATERAL generate_series(0, t.combo_count - 1) AS i(combo_index)
        JOIN   radix  r ON r.option_id = t.option_id
        JOIN   member m ON m.option_id    = t.option_id
                       AND m.axis_index   = r.axis_index
                       AND m.member_index = (i.combo_index / r.multiplier) % r.size
    )
    -- options without a combination spec, on their own
    SELECT b.option_code AS option_code
    FROM   base b
    WHERE  NOT EXISTS (SELECT 1 FROM axis a WHERE a.option_id = b.option_id)
    UNION ALL
    -- base option combined with one member of every axis
    SELECT b.option_code || ';' || string_agg(p.option_code, ';' ORDER BY p.axis_index)
    FROM   picked p
    JOIN   base b ON b.option_id = p.option_id
    GROUP  BY b.option_code, p.combo_index
    ORDER  BY 1;
END;
$$;

alter function crud_xbom() owner to xfw3;

