create table forecast
(
	forecast_id integer generated always as identity
		constraint pk_mock_forecast
			primary key,
	domain_id integer default 1 not null,
	material_id integer,
	forecast_date date not null,
	expected_sqm numeric,
	created_at timestamp with time zone default CURRENT_TIMESTAMP
);

alter table forecast owner to xfw3;

