create table imposition_log
(
	imposition_log_id bigint generated always as identity
		primary key,
	imposition_id bigint not null
		constraint imposition_log_nest_id_fkey
			references imposition,
	from_status_sequence integer,
	to_status_sequence integer,
	amount integer not null,
	remaining_impact_delta integer not null,
	resource_uids text[] default '{}'::text[] not null,
	moved_at timestamp with time zone default now() not null,
	constraint imposition_log_move_valid
		check ((from_status_sequence IS NOT NULL) OR (to_status_sequence IS NOT NULL)),
	constraint imposition_log_no_self
		check (from_status_sequence IS DISTINCT FROM to_status_sequence)
);

alter table imposition_log owner to xfw3;

create index imposition_log_imposition_id_idx
	on imposition_log (imposition_id);

