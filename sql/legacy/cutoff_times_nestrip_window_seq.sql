create sequence cutoff_times_nestrip_window_seq
	as integer;

alter sequence cutoff_times_nestrip_window_seq owner to xfw3;

alter sequence cutoff_times_nestrip_window_seq owned by cutoff_times.nest_rip_window_seconds;

