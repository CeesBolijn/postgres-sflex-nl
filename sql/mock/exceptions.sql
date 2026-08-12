create table exceptions
(
	exception_id integer generated always as identity
		constraint pk_mock_exceptions
			primary key,
	domain_id integer default 1 not null,
	resource_uid text,
	exception_date date not null,
	exception_type text,
	remarks text,
	created_at timestamp with time zone default CURRENT_TIMESTAMP
);

alter table exceptions owner to xfw3;

