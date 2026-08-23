create table data
(
	data_log_id bigint generated always as identity
		constraint pk_data_log
			primary key,
	resource_uid text not null,
	filename text,
	nest_id integer,
	spec_id integer,
	amount numeric,
	sub_set text,
	start_at timestamp with time zone not null,
	end_at timestamp with time zone,
	metrics_json jsonb default '[]'::jsonb not null,
	source text not null,
	source_ref text,
	source_ts timestamp with time zone,
	ingested_at timestamp with time zone default now() not null,
	nest_name text,
	production_time_seconds integer,
	step text,
	page_number integer,
	data_json jsonb
);

alter table data owner to xfw3;

create unique index uq_data_log_source_ref
	on data (source, source_ref)
	where (source_ref IS NOT NULL);

create index ix_data_resource_time
	on data (resource_uid, start_at);

-- nest lookups (get_nest_detail, get_nest_list) find their rows by nest_name
create index ix_data_nest_time
	on data (nest_name, start_at)
	where nest_name is not null;

