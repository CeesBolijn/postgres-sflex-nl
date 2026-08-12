create table production_forecast
(
	date date not null,
	production_line_id integer not null,
	production_company_id integer not null,
	is_holiday boolean,
	budget_m2_last_6_weeks numeric,
	actual_m2_last_6_weeks numeric,
	performance_factor numeric,
	revenue_forecast numeric,
	m2_forecast numeric,
	production_orders_forecast numeric,
	updated_at timestamp with time zone default now(),
	constraint pk_production_forecast
		primary key (date, production_line_id, production_company_id)
);

alter table production_forecast owner to xfw3;

