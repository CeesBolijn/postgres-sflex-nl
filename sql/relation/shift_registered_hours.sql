create table shift_registered_hours
(
	shift_registered_hours_id bigserial
		primary key,
	resource_uid text not null,
	content_id text not null
		unique,
	log_type text not null,
	shift_type text not null,
	start_at timestamp with time zone not null,
	end_at timestamp with time zone not null,
	resource_data_json jsonb not null,
	original_json jsonb,
	created_at timestamp with time zone default now() not null,
	updated_at timestamp with time zone default now() not null
);

alter table shift_registered_hours owner to xfw3;

create index shift_registered_hours_resource_uid_idx
	on shift_registered_hours (resource_uid);

create index shift_registered_hours_start_at_idx
	on shift_registered_hours (start_at);

