create table nest
(
	batch_uid bigint,
	domain_id integer not null,
	nest_id bigint not null
		constraint uq_nest_id
			unique,
	nest_counter integer default 1 not null,
	reproduced_counter integer default 0 not null,
	nest_name text,
	amount integer,
	width numeric(8,2),
	height numeric(8,2),
	nest_json jsonb,
	sort_order integer,
	status_json jsonb default '[{"xBomStateId": 1}]'::jsonb,
	possible_states bigint,
	possible_multiple_states bigint,
	nest_uid bigint generated always as identity
		constraint pk_production_nest
			primary key,
	nested_at timestamp with time zone,
	updated_at timestamp with time zone,
	batch_id integer generated always as (((nest_json ->> 'batch_id'::text))::integer) stored,
	bucket_name text generated always as (substr((nest_json ->> 'printfile_name'::text), (strpos((nest_json ->> 'printfile_name'::text), '_'::text) + 1))) stored
);

alter table nest owner to xfw3;

create index idx_production_nest_name_batch_uid
	on nest (nest_name, batch_uid);

create index idx_nest_valid_thumbnail
	on nest (nest_name asc, nested_at desc) include (nest_id)
	where (((nest_json -> 'job_thumbnail'::text) IS NOT NULL) AND (((nest_json -> 'job_thumbnail'::text) ->> '_error'::text) IS NULL));

create index idx_nest_batch_uid
	on nest (batch_uid)
	where (batch_uid IS NOT NULL);

create index idx_nest_batch_id
	on nest ((nest_json ->> 'batch_id'::text));

create index idx_nest_batch_id_int
	on nest (((nest_json ->> 'batch_id'::text)::integer));

create index idx_nest_material_id
	on nest (((nest_json ->> 'material_id'::text)::integer));

