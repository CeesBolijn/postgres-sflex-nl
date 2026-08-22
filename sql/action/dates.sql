create table dates
(
	date date not null
		constraint pk_dates
			primary key,
	weekday smallint not null,
	is_weekend boolean not null,
	is_mandatory_day_off boolean default false not null,
	-- the tenants that have this day off; replaces the boolean
	-- is_mandatory_day_off, which stays until every reader is adapted
	tenants_mandatory_day_off integer[] default '{}'::integer[] not null
);

alter table dates owner to xfw3;

create index idx_action_dates_working_days
	on dates (weekday, date);
