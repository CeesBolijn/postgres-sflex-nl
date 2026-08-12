create table nest_queue
(
	nest_queue_id integer generated always as identity
		constraint pk_mock_nest_queue
			primary key,
	material_ids integer[],
	name text,
	nest_queue_guid uuid
);

alter table nest_queue owner to xfw3;

