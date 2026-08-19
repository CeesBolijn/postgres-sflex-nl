create table nav
(
	nav_id integer generated always as identity
		primary key,
	nav text not null
		unique,
	nav_json jsonb,
	company_ids jsonb
);

alter table nav owner to xfw3;

