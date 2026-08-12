create function get_nest_status(p_nest_ids bigint[], p_domain_id integer DEFAULT 1) returns TABLE(nest_id bigint, code text, status_sequence integer, current_amount bigint, last_moved_at timestamp with time zone, last_resource_uids text[])
	stable
	language sql
as $$
    WITH m AS (
        -- Unpivot each log row into two signed entries: arrival at to_status, departure from from_status
        SELECT DISTINCT ON (nl.nest_id, v.status_sequence)
            nl.nest_id,
            v.status_sequence,
            SUM(v.delta) OVER (PARTITION BY nl.nest_id, v.status_sequence) AS current_amount,
            -- Only inflow rows carry moved_at / resource_uids; outflow yields NULL
            CASE WHEN v.is_inflow THEN nl.moved_at END      AS last_moved_at,
            CASE WHEN v.is_inflow THEN nl.resource_uids END AS last_resource_uids
        FROM legacy.nest_log nl
        CROSS JOIN LATERAL (VALUES
            (nl.to_status_sequence,    nl.amount, true),
            (nl.from_status_sequence, -nl.amount, false)
        ) AS v(status_sequence, delta, is_inflow)
        WHERE nl.nest_id = ANY(p_nest_ids)
          AND v.status_sequence IS NOT NULL
        -- Inflow first, then newest: keeps the most recent arrival per status
        ORDER BY nl.nest_id, v.status_sequence, v.is_inflow DESC, nl.moved_at DESC
    )
    SELECT
        m.nest_id,
        s.code,
        m.status_sequence,
        m.current_amount,
        m.last_moved_at,
        m.last_resource_uids
    FROM m
    JOIN mapping.internal_status s
        ON s.sequence   = m.status_sequence
        AND s.domain_id = p_domain_id
    WHERE m.current_amount > 0
    ORDER BY m.nest_id, m.status_sequence;
$$;

alter function get_nest_status(bigint[], integer) owner to xfw3;

