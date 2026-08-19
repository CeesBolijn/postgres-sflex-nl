create table company_address
(
	company_id integer not null
		constraint company_address_company_company_id_fk
			references company,
	address_id integer not null
		constraint company_address_address_address_id_fk
			references address,
	sort_order integer,
	constraint company_address_pk
		primary key (address_id, company_id)
);

alter table company_address owner to xfw3;

