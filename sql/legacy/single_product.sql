create table single_product
(
	single_product_id integer generated always as identity
		constraint single_product_pk
			primary key,
	single_product_json jsonb,
	nest_uid bigint,
	nas_id integer,
	file_uid text,
	status text,
	x_bom_state_id integer,
	created_at timestamp with time zone default now(),
	filename text,
	amount integer,
	nest_id integer,
	production_orderline_id integer generated always as (((single_product_json ->> 'production_orderline_id'::text))::integer) stored,
	constraint uq_single_product_nest_filename_amount
		unique (nest_id, filename, amount)
);

alter table single_product owner to xfw3;

create index idx_single_product_nest_id
	on single_product (nest_id);

create index idx_single_product_pol_id
	on single_product (production_orderline_id);

