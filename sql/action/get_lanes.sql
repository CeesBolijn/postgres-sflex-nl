create function get_lanes(p_lane_id bigint[], p_rule_path text, p_plan_date date, p_start_offset_in_seconds integer DEFAULT 79200, p_work_during_breaks boolean DEFAULT false) returns TABLE(lane_id bigint, sort_order numeric, duration_in_seconds integer, non_working_time_in_seconds integer, start_in_seconds integer, end_in_seconds integer)
	stable
	language sql
as $$
    WITH break_map AS (
        -- Each window on the net axis: axis position minus the window time before it.
        SELECT w.duration_in_seconds AS dur,
               action.to_axis_seconds(w.start_offset_in_seconds, p_start_offset_in_seconds)
                 - coalesce(sum(w.duration_in_seconds) OVER (
                       ORDER BY action.to_axis_seconds(w.start_offset_in_seconds, p_start_offset_in_seconds)
                       ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0)::int AS net_at
        FROM action.get_non_working_times(p_rule_path, p_plan_date) w
        WHERE NOT (w.type = 'break' AND p_work_during_breaks)
    ),
    net AS (
        -- One span per lane: the summed working time, anchored at the origin.
        SELECT l.lane_id, l.sort_order,
               coalesce(sum(i.duration_in_seconds), 0)::int AS duration_in_seconds,
               p_start_offset_in_seconds AS net_start
        FROM action.lane l
        LEFT JOIN action.lane_item i USING (lane_id)
        WHERE l.lane_id = ANY (p_lane_id)
        GROUP BY l.lane_id, l.sort_order
    )
    SELECT n.lane_id, n.sort_order, n.duration_in_seconds,
           e.cum - s.cum                               AS non_working_time_in_seconds,
           n.net_start + s.cum                         AS start_in_seconds,
           n.net_start + n.duration_in_seconds + e.cum AS end_in_seconds
    FROM net n
    CROSS JOIN LATERAL (
        SELECT coalesce(sum(b.dur), 0)::int AS cum
        FROM break_map b WHERE b.net_at <= n.net_start
    ) s
    CROSS JOIN LATERAL (
        SELECT coalesce(sum(b.dur), 0)::int AS cum
        FROM break_map b WHERE b.net_at < n.net_start + n.duration_in_seconds
    ) e
    ORDER BY n.sort_order, n.lane_id;
$$;

alter function get_lanes(bigint[], text, date, integer, boolean) owner to xfw3;

