create table xbom
(
	xbom_id integer generated always as identity
		constraint pk_catalog_xbom
			primary key,
	option_code text,
	item_code text
		references item (item_code),
	-- the formula by code, not by row: the version that applies is picked
	-- at read time by date (catalog.get_formula)
	formula_code text,
	scope text default 'unit'::text not null,
	param_json jsonb default '{}'::jsonb not null,
	config_json jsonb default '{}'::jsonb not null,
	version integer default 1 not null,
	version_status text default 'active'::text not null,
	created_at timestamp with time zone default now() not null,
	sort_order integer
);

alter table xbom owner to xfw3;

create index idx_catalog_xbom_item_code
	on xbom (item_code);

create index idx_catalog_xbom_formula_code
	on xbom (formula_code);

create unique index uq_catalog_xbom
	on xbom (option_code, item_code, scope);

