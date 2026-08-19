create table address
(
	address_id integer generated always as identity
		constraint address_pk
			primary key,
	address_type text,
	attn text,
	street text,
	no text,
	no_addition text,
	zip text,
	place text,
	country text,
	country_code text,
	longitude double precision,
	latitude double precision,
	active boolean default true
);

alter table address owner to xfw3;

create unique index address_address_id_uindex
	on address (address_id);

