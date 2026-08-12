create table status
(
	code text not null
		primary key,
	sequence integer not null
		unique,
	phase text not null,
	created_at timestamp with time zone default now() not null,
	updated_at timestamp with time zone default now() not null
);

alter table status owner to xfw3;

create index idx_status_phase
	on status (phase);

