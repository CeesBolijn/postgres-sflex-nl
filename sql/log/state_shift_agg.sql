create table state_shift_agg
(
	shift_date date not null,
	shift_index integer not null,
	resource_uid text not null,
	state text not null,
	shift_start timestamp with time zone not null,
	shift_end timestamp with time zone not null,
	duration_seconds numeric not null,
	constraint pk_state_shift_agg
		primary key (shift_date, shift_index, resource_uid, state)
);

alter table state_shift_agg owner to xfw3;

