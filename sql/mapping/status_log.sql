create table status_log
(
	status_log_id integer generated always as identity
		constraint pk_mapping_status_log_clean
			primary key,
	domain_id integer,
	object_id integer,
	line_json jsonb,
	updated_at timestamp,
	log_id text,
	previous_internal_status_id integer,
	update_internal_status_id integer,
	next_internal_status_id integer,
	constraint uq_status_log_domain_object_updated
		unique (domain_id, object_id, updated_at)
);

alter table status_log owner to xfw3;

create index status_log_log_id_index
	on status_log (log_id);

create index status_log_clean_updated_at_index
	on status_log (updated_at);

