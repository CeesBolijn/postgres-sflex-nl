create table production_status
(
	production_status_id integer generated always as identity
		constraint pk_mock_production_status_check
			primary key,
	production_orderline_id integer not null,
	production_order_status text not null
);

alter table production_status owner to xfw3;

