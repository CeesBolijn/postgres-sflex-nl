create table data_group
(
	data_group_id integer generated always as identity
		primary key,
	data_group text not null
		unique,
	data_group_json jsonb default '{}'::jsonb
);

alter table data_group owner to xfw3;

