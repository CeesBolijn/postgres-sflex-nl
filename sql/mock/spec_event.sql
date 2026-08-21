create table spec_event
(
	spec_event_id bigint generated always as identity
		primary key,
	spec_id bigint not null
		references spec,
	from_status_sequence integer,
	to_status_sequence integer,
	amount integer not null,
	remaining_impact_delta integer,
	resource_uids text[] default '{}'::text[] not null,
	moved_at timestamp with time zone default now() not null,
	constraint spec_event_move_valid
		check ((from_status_sequence IS NOT NULL) OR (to_status_sequence IS NOT NULL)),
	constraint spec_event_no_self
		check (from_status_sequence IS DISTINCT FROM to_status_sequence)
);

alter table spec_event owner to xfw3;

create index spec_event_spec_id_idx
	on spec_event (spec_id);

