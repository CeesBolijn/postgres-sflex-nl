create table log
(
	log_id bigint generated always as identity
		constraint pk_production_log
			primary key,
	created_date_time timestamp with time zone default CURRENT_TIMESTAMP,
	log_json jsonb,
	type text,
	content_id text,
	last_modified_at timestamp with time zone default CURRENT_TIMESTAMP not null
);

alter table log owner to xfw3;

create index idx_log_type_content_id
	on log (type, content_id);

