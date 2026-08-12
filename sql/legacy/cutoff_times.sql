create table cutoff_times
(
	cut_off_time_id integer generated always as identity
		constraint pk_production_cut_off_times
			primary key,
	service_provider_id integer,
	type text,
	delivery_hours integer,
	cut_off_time time with time zone,
	threshold integer,
	threshold_json jsonb,
	group_id integer,
	nest_rip_window_seconds integer
);

comment on column cutoff_times.nest_rip_window_seconds is 'nestrip_window in seconds';

alter table cutoff_times owner to xfw3;

