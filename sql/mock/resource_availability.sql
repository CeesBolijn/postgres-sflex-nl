create table resource_availability
(
	resource_availability_id bigint generated always as identity
		primary key,
	weekday smallint not null
		constraint resource_availability_weekday_check
			check ((weekday >= 1) AND (weekday <= 7)),
	resource_uid text not null,
	start_offset_in_seconds integer not null
		constraint resource_availability_start_offset_in_seconds_check
			check ((start_offset_in_seconds >= 0) AND (start_offset_in_seconds <= 86399)),
	duration_in_seconds integer not null
		constraint resource_availability_duration_in_seconds_check
			check (duration_in_seconds >= 0),
	moved_at timestamp with time zone default now() not null,
	constraint resource_availability_weekday_resource_uid_start_offset_in__key
		unique (weekday, resource_uid, start_offset_in_seconds)
);

alter table resource_availability owner to xfw3;

