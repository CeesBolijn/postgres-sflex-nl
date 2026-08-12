create table instance_option_set
(
	instance_option_set_id integer generated always as identity
		constraint pk_catalog_instance_option_set
			primary key,
	instance_option_tree_id integer not null
		constraint fk_instance_option_set_instance_option_tree
			references instance_option_tree,
	option_set_id integer not null,
	sort_order integer,
	option_set_code text,
	option_set_json jsonb,
	option_codes_json jsonb
);

alter table instance_option_set owner to xfw3;

