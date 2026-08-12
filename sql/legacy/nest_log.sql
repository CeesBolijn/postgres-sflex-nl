create table nest_log
(
	nest_log_id bigint generated always as identity
		primary key,
	nest_id bigint not null
		references nest (nest_id),
	from_status_sequence integer,
	to_status_sequence integer,
	amount integer not null,
	remaining_impact_delta integer,
	resource_uids text[] default '{}'::text[] not null,
	moved_at timestamp with time zone default now() not null,
	batch_id integer,
	constraint nest_log_move_valid
		check ((from_status_sequence IS NOT NULL) OR (to_status_sequence IS NOT NULL)),
	constraint nest_log_no_self
		check (from_status_sequence IS DISTINCT FROM to_status_sequence)
);

alter table nest_log owner to xfw3;

create index nest_log_nest_id_idx
	on nest_log (nest_id);

create index nest_log_nest_id_to_status_idx
	on nest_log (nest_id, to_status_sequence);

create index nest_log_nest_id_moved_at_idx
	on nest_log (nest_id asc, moved_at desc);

create index nest_log_to_status_sequence_idx
	on nest_log (to_status_sequence);

create index idx_nest_log_batch_id
	on nest_log (batch_id);

create index idx_nest_log_batch_id_to_status
	on nest_log (batch_id, to_status_sequence);

