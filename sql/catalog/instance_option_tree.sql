create table instance_option_tree
(
	instance_option_tree_id integer generated always as identity
		constraint pk_catalog_instance_option_tree
			primary key,
	code text,
	product_json jsonb,
	version integer,
	version_status text default 'active'::text,
	created_at timestamp with time zone default now()
);

alter table instance_option_tree owner to xfw3;

