create function legacy.get_batch_status(p_batch_id integer) returns jsonb
	language sql
as $$
    -- current amount per status summed across the batch's nests,
    -- with last_moved_at / last_resource_uids from the most recent inflow per status
    WITH log AS (
        SELECT nl.*
        FROM legacy.nest_log nl
        JOIN legacy.nest n ON n.nest_id = nl.nest_id
        WHERE n.batch_id = p_batch_id
    ),
    balances AS (
        SELECT
            s.code,
            s.sequence,
            COALESCE(sum(log.amount) FILTER (WHERE log.to_status_sequence = s.sequence), 0)
                - COALESCE(sum(log.amount) FILTER (WHERE log.from_status_sequence = s.sequence), 0) AS current_amount,
            last_in.moved_at AS last_moved_at,
            last_in.resource_uids AS last_resource_uids
        FROM mapping.internal_status s
        LEFT JOIN log
          ON log.to_status_sequence = s.sequence OR log.from_status_sequence = s.sequence
        -- Fetch the most recent inflow row for this status directly, instead of
        -- array_agg(...)[1], which breaks when resource_uids is an empty array for some rows
        LEFT JOIN LATERAL (
            SELECT l.moved_at, l.resource_uids
            FROM log l
            WHERE l.to_status_sequence = s.sequence
            ORDER BY l.moved_at DESC
            LIMIT 1
        ) last_in ON TRUE
        GROUP BY s.code, s.sequence, last_in.moved_at, last_in.resource_uids
    )
    SELECT jsonb_agg(to_jsonb(b) ORDER BY b.sequence)
    FROM balances b
    WHERE b.current_amount > 0;
$$;

alter function legacy.get_batch_status(integer) owner to xfw3;

