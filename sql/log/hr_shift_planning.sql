create table hr_shift_planning
(
	shift_planning_id integer generated always as identity
		constraint pk_shift_planning
			primary key,
	department_group_id integer not null,
	business_date date not null,
	shift_json jsonb default '{}'::jsonb not null,
	updated_at timestamp with time zone default now() not null,
	constraint uq_shift_planning
		unique (department_group_id, business_date)
);

alter table hr_shift_planning owner to xfw3;

create index ix_shift_planning_date
	on hr_shift_planning (business_date, department_group_id);

