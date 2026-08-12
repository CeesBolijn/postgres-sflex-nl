create table error
(
	error_log_id bigint generated always as identity
		constraint pk_error_log
			primary key,
	resource_uid text not null,
	start_at timestamp with time zone not null,
	end_at timestamp with time zone,
	code text,
	severity text,
	message text,
	context_json jsonb default '{}'::jsonb not null,
	source text not null,
	source_ref text,
	source_ts timestamp with time zone,
	ingested_at timestamp with time zone default now() not null,
	page_number integer,
	constraint uq_error_log
		unique (resource_uid, start_at, code, source)
);

alter table error owner to xfw3;

create index ix_error_resource_time
	on error (resource_uid, start_at);

create index error_resource_uid_start_at_idx
	on error (resource_uid, start_at);

