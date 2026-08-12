create table library_option_set
(
	option_set_id integer generated always as identity
		primary key,
	collection_id integer,
	option_set text,
	option_set_json jsonb,
	sort_order integer,
	version integer default 1,
	status text default 'active'::text,
	created_at timestamp with time zone default now() not null
);

alter table library_option_set owner to xfw3;

