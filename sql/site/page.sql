create table page
(
	page_id integer generated always as identity
		primary key,
	path jsonb default '{}'::jsonb not null,
	environment jsonb default '{}'::jsonb not null
);

alter table page owner to xfw3;

