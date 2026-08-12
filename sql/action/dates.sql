create table dates
(
	date date not null
		constraint pk_dates
			primary key,
	weekday smallint not null,
	is_weekend boolean not null,
	is_mandatory_day_off boolean default false not null,
	tenant_id integer,
	shift_json jsonb
);

alter table dates owner to xfw3;

create index idx_action_dates_working_days
	on dates (weekday, date);

