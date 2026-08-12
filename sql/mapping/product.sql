create table product
(
	product_id integer not null
		constraint pk_mapping_product
			primary key,
	material_id integer not null,
	production_start_date date not null,
	production_interval integer,
	updated_at timestamp with time zone default now() not null
);

alter table product owner to xfw3;

create index ix_mapping_product_material_id
	on product (material_id);

