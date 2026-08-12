create table sales_orderline_option
(
	id integer not null
		primary key,
	domain_id integer not null,
	sales_orderline_id integer not null,
	option_type_code text,
	option_title_base text,
	option_internal_description text,
	option_input_value text,
	parent_type_code text,
	parent_title_base text,
	updated_at timestamp with time zone default CURRENT_TIMESTAMP,
	material_id integer,
	api_code text,
	product_api_code text,
	option_code text,
	option_codes text[]
);

alter table sales_orderline_option owner to xfw3;

create index idx_sol_option_orderline
	on sales_orderline_option (sales_orderline_id);

create index idx_sol_option_type_code
	on sales_orderline_option (option_type_code);

create index ix_sales_orderline_option_lookup
	on sales_orderline_option (sales_orderline_id, parent_title_base);

create index ix_sol_option_orderline_parent
	on sales_orderline_option (sales_orderline_id, parent_title_base) include (option_title_base);

