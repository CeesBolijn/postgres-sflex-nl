create table non_working_times
(
	non_working_time_id bigint generated always as identity
		primary key,
	type text default 'break'::text not null,
	rule_path text not null
		constraint non_working_times_rule_path_check
			check (rule_path ~ '^[0-9]+(\.[0-9]+)*$'::text),
	weekday smallint
		constraint non_working_times_weekday_check
			check ((weekday >= 1) AND (weekday <= 7)),
	start_offset_in_seconds integer not null
		constraint non_working_times_start_offset_in_seconds_check
			check ((start_offset_in_seconds >= 0) AND (start_offset_in_seconds <= 86399)),
	duration_in_seconds integer not null
		constraint non_working_times_duration_in_seconds_check
			check (duration_in_seconds >= 0),
	moved_at timestamp with time zone default now() not null,
	moved_by text default CURRENT_USER not null,
	constraint non_working_times_rule_path_weekday_type_start_offset_in_se_key
		unique nulls not distinct (rule_path, weekday, type, start_offset_in_seconds, non_working_time_id)
);

alter table non_working_times owner to xfw3;

