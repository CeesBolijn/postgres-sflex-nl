create table object
(
	action_id integer generated always as identity
		constraint pk_action_object
			primary key,
	domain_id integer not null,
	company_id integer,
	contact_id integer,
	team_id bigint,
	action_json jsonb,
	roles bigint default 65535 not null,
	parent_action_id integer,
	section_id integer,
	created_at timestamp with time zone default CURRENT_TIMESTAMP,
	start_at timestamp with time zone,
	end_at timestamp with time zone,
	status_sequence_id integer,
	standard_production_impact integer,
	resource_uid text,
	resource_plan_rank numeric default 1000 not null,
	is_fixed_offset boolean default false not null,
	is_atomic boolean default false,
	offset_in_seconds integer,
	batch_id integer
);

alter table object owner to xfw3;

create index idx_action_object_action_id
	on object (action_id);

create index idx_action_object_section_id
	on object (section_id);

create index idx_action_object_batch_id
	on object (batch_id);

create unique index uq_action_object_plannable_item_id
	on object (((action_json ->> 'plannable_item_id'::text)::integer));

