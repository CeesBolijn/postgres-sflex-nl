create table state
(
	state_log_id bigint generated always as identity
		constraint pk_state_log
			primary key,
	resource_uid text not null,
	state text not null,
	reason text,
	start_at timestamp with time zone not null,
	detail jsonb default '{}'::jsonb not null,
	source text not null,
	source_ref text,
	source_ts timestamp with time zone,
	ingested_at timestamp with time zone default now() not null,
	page_number integer,
	constraint uq_state_log
		unique (resource_uid, start_at, state, source)
);

alter table state owner to xfw3;

create index ix_state_resource_time
	on state (resource_uid, start_at);

create unique index uq_state_source_ref_state
	on state (source, source_ref, state)
	where (source_ref IS NOT NULL);

create index idx_log_state_resource_start
	on state (resource_uid asc, start_at desc);

