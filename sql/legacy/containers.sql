create table containers
(
	container_id integer generated always as identity
		constraint pk_production_containers
			primary key,
	container_name text,
	assigned_line text,
	status boolean,
	color text,
	last_update timestamp with time zone default now(),
	x_pos integer,
	y_pos integer
);

alter table containers owner to xfw3;

