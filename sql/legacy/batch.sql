create table batch
(
	batch_uid integer generated always as identity
		constraint pk_production_batch
			primary key,
	domain_id integer not null,
	batch_id integer not null
		constraint uq_batch_id
			unique,
	batch_counter integer default 1 not null,
	batch_at timestamp with time zone,
	batch_name text,
	x_bom text,
	batch_json jsonb,
	is_locked boolean default false,
	status text default '[{"batchStateId":1}]'::text,
	year_week_day_timeslot_index integer,
	batch_state_id integer generated always as (((batch_json ->> '$[0].batchStateId'::text))::integer) stored,
	width numeric(10,1),
	height numeric(10,1),
	updated_at timestamp with time zone,
	material_id integer generated always as (((batch_json ->> 'material_id'::text))::integer) stored
);

alter table batch owner to xfw3;

create index idx_batch_production_line_id
	on batch (((batch_json ->> 'production_line_id'::text)::integer));

create index idx_batch_material_id
	on batch (material_id);

