create function action.to_axis_seconds(p_clock_seconds integer, p_start_offset_in_seconds integer DEFAULT 79200) returns integer
	immutable
	parallel safe
	language sql
as $$
    SELECT (p_clock_seconds - p_start_offset_in_seconds + 86400) % 86400
           + p_start_offset_in_seconds;
$$;

alter function action.to_axis_seconds(integer, integer) owner to xfw3;

