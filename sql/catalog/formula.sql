create table formula
(
	formula_id text not null
		primary key,
	description text not null,
	formula_json jsonb not null,
	formule_level integer default 0 not null,
	version integer default 1 not null,
	status text default 'active'::text not null,
	created_at timestamp with time zone default now() not null
);

alter table formula owner to xfw3;

