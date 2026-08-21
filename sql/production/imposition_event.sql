create table imposition_event
(
	imposition_event_id bigint generated always as identity
		primary key,
	imposition_id bigint not null
		constraint imposition_event_imposition_id_fkey
			references imposition,
	from_status_sequence integer,
	to_status_sequence integer,
	amount integer not null,
	remaining_impact_delta integer not null,
	resource_uids text[] default '{}'::text[] not null,
	moved_at timestamp with time zone default now() not null,
	constraint imposition_event_move_valid
		check ((from_status_sequence IS NOT NULL) OR (to_status_sequence IS NOT NULL)),
	constraint imposition_event_no_self
		check (from_status_sequence IS DISTINCT FROM to_status_sequence)
);

alter table imposition_event owner to xfw3;

create index imposition_event_imposition_id_idx
	on imposition_event (imposition_id);

