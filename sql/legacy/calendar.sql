create table calendar
(
	calendar_id integer generated always as identity
		constraint pk_production_calendar
			primary key,
	item_code text,
	reference_date date,
	interval_days integer
);

alter table calendar owner to xfw3;

