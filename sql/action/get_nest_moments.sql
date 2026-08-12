create function get_nest_moments(p_nest_moment_codes text[]) returns jsonb
	stable
	parallel safe
	language sql
as $$
    -- Resolves nest_moment_codes (e.g. {18}, {48-multiple-early, 96})
    -- against lookup_nest_moments and returns one flat jsonb array of the
    -- moments, deduplicated on content and ordered by nest moment.
    -- Without delivery_time in the elements, identical times shared by
    -- several codes (e.g. the 20:00 slot in every -multiple- variant)
    -- collapse into one entry, which is the point of removing it.
    -- Unknown codes contribute nothing; null or empty input yields '[]'.
    SELECT coalesce(jsonb_agg(m.moment ORDER BY m.moment_abs), '[]'::jsonb)
    FROM (
        SELECT DISTINCT
            nm.value AS moment,
            coalesce((nm.value -> 'nest_time' ->> 'day_offset')::integer, 0) * 86400
                + EXTRACT(EPOCH FROM (nm.value -> 'nest_time' ->> 'time')::timetz)::integer
                     AS moment_abs
        FROM production.lookup l
        CROSS JOIN LATERAL jsonb_array_elements(l.lookup_json) AS c(value)
        CROSS JOIN LATERAL jsonb_array_elements(c.value -> 'nest_moments') AS nm(value)
        WHERE l.lookup = 'lookup_nest_moments'
          AND c.value ->> 'code' = ANY (p_nest_moment_codes)
    ) m;
$$;

alter function get_nest_moments(text[]) owner to xfw3;

