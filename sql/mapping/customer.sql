-- One row per customer, fed by crud_component_specs_orderline (newest
-- company_name wins); mapping.get_customers searches it for the filters.
create table customer
(
	customer_id integer not null
		constraint pk_mapping_customer
			primary key,
	company_name text not null,
	updated_at timestamp with time zone default now() not null
);

alter table customer owner to xfw3;
