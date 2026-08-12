create function get_non_working_times(p_rule_path text, p_plan_date date) returns TABLE(type text, start_offset_in_seconds integer, duration_in_seconds integer)
	stable
	language sql
as $$
    WITH current AS (
        SELECT DISTINCT ON (n.rule_path, n.weekday, n.type, n.start_offset_in_seconds)
               length(n.rule_path) AS specificity,
               n.type, n.start_offset_in_seconds, n.duration_in_seconds
        FROM action.non_working_times n
        WHERE (p_rule_path || '.') LIKE (n.rule_path || '.%')
          AND (n.weekday IS NULL OR n.weekday = extract(dow FROM p_plan_date)::smallint + 1)
        ORDER BY n.rule_path, n.weekday, n.type, n.start_offset_in_seconds,
                 n.non_working_time_id DESC
    )
    SELECT type, start_offset_in_seconds, duration_in_seconds
    FROM (SELECT c.*, max(specificity) OVER (PARTITION BY type) AS winning FROM current c) w
    WHERE specificity = winning AND duration_in_seconds > 0;
$$;

alter function get_non_working_times(text, date) owner to xfw3;

