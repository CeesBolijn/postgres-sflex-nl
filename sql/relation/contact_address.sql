create table contact_address
(
	contact_id integer not null
		constraint contact_address_contact_contact_id_fk
			references contact,
	address_id integer not null
		constraint contact_address_address_address_id_fk
			references address,
	constraint contact_address_pk
		primary key (address_id, contact_id)
);

alter table contact_address owner to xfw3;

