create table dimension_check
(
	dimension_check_id integer generated always as identity
		constraint pk_mock_dimension_check
			primary key,
	production_order_id integer,
	production_orderline_id integer not null,
	material_id integer,
	width numeric not null,
	height numeric not null,
	resource_uids text[] not null,
	created_at timestamp with time zone default CURRENT_TIMESTAMP
);

alter table dimension_check owner to xfw3;

