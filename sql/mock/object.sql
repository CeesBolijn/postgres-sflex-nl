create table object
(
	action_id integer generated always as identity
		constraint pk_mock_object
			primary key,
	domain_id integer not null,
	action_json jsonb,
	parent_action_id integer,
	created_at timestamp with time zone default CURRENT_TIMESTAMP,
	start_at timestamp with time zone,
	standard_production_impact integer,
	resource_uid text,
	resource_plan_rank numeric default 1000 not null,
	is_fixed_offset boolean default false not null,
	is_atomic boolean default false,
	offset_in_seconds integer
);

alter table object owner to xfw3;

create index idx_mock_object_action_id
	on object (action_id);

