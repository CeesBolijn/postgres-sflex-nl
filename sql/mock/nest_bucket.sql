create table nest_bucket
(
	nest_bucket_id integer generated always as identity
		constraint pk_mock_nest_bucket
			primary key,
	nest_queue_id integer not null,
	production_location text,
	width numeric,
	min_height numeric,
	max_height numeric,
	resource_json jsonb,
	created_at timestamp with time zone default CURRENT_TIMESTAMP
);

alter table nest_bucket owner to xfw3;

create index ix_mock_nest_bucket_material
	on nest_bucket (production_location);

