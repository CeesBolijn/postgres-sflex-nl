create table library_option
(
	option_id integer generated always as identity
		primary key,
	option_set_id integer,
	option_code text,
	option_json jsonb,
	sort_order integer,
	version integer default 1,
	version_status text default 'active'::text,
	created_at timestamp with time zone default now() not null,
	option_set_ids integer[]
);

alter table library_option owner to xfw3;

