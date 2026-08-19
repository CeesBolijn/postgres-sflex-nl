create table block
(
	block_id integer generated always as identity
		primary key,
	block_json jsonb,
	languages jsonb default '[]'::jsonb,
	hidden boolean default false not null,
	roles jsonb default '[]'::jsonb,
	company_ids jsonb default '[]'::jsonb
);

alter table block owner to xfw3;

