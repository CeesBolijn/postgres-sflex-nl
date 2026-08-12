create table data_duration_check
(
	data_duration_check_id bigint generated always as identity
		primary key,
	data_log_id bigint not null
		unique,
	resource_uid text,
	nest_name text,
	old_seconds integer,
	checked_at timestamp with time zone default now() not null
);

alter table data_duration_check owner to xfw3;

