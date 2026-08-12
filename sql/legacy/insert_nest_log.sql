create function insert_nest_log(p_nest_name text) returns void
	language sql
as $$
    WITH status_ordered AS (
        SELECT
            l.step,
            l.sequence,
            lag(l.sequence) OVER (ORDER BY l.sequence) AS from_sequence
        FROM relation.lookup rl,
             jsonb_to_recordset(rl.lookup_json) AS l(step text, sequence int)
        WHERE rl.lookup = 'lookup_step_category'
          AND l.step IN (SELECT step FROM legacy.get_nest_relevant_steps(p_nest_name))
    )
    INSERT INTO legacy.nest_log
        (batch_id, nest_id, from_status_sequence, to_status_sequence, amount, remaining_impact_delta, resource_uids, moved_at)
    SELECT
        n.batch_id,
        n.nest_id,
        so.from_sequence,
        so.sequence,
        d.amount,
        NULL,
        ARRAY[d.resource_uid],
        d.start_at
    FROM log.data d
    JOIN status_ordered so ON so.step = d.step
    JOIN legacy.nest n ON n.nest_name = d.nest_name
    WHERE d.nest_name = p_nest_name
      AND NOT EXISTS (
          SELECT 1
          FROM legacy.nest_log nl
          WHERE nl.nest_id = n.nest_id
            AND nl.to_status_sequence = so.sequence
            AND nl.moved_at = d.start_at
      );
$$;

alter function insert_nest_log(text) owner to xfw3;

