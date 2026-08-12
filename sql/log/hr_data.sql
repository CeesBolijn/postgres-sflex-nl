create table hr_data
(
	hr_data_log_id integer generated always as identity
		constraint pk_hr_data_log
			primary key,
	employee_id integer not null,
	department_id integer,
	department_group_id integer,
	business_date date not null,
	shift text not null,
	start_at timestamp with time zone,
	end_at timestamp with time zone,
	source text default 'dyflexis'::text not null,
	source_ref text,
	ingested_at timestamp with time zone default now() not null,
	updated_at timestamp with time zone default now() not null,
	constraint uq_hr_data_log
		unique (employee_id, business_date, shift)
);

alter table hr_data owner to xfw3;

