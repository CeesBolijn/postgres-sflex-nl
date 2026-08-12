create table nest_document
(
	nest_document_id integer generated always as identity
		constraint pk_mock_nest_document
			primary key,
	nest_job_id integer not null
		constraint fk_nbd_bucket
			references nest_job,
	production_orderline_id integer not null,
	amount numeric not null,
	created_at timestamp with time zone default CURRENT_TIMESTAMP,
	nest_id integer,
	width numeric,
	height numeric not null
);

alter table nest_document owner to xfw3;

create index ix_mock_nbd_bucket
	on nest_document (nest_job_id);

