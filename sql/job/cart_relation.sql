create table cart_relation
(
	cart_id integer not null
		constraint cart_relation_cart_cart_id_fk
			references cart,
	company_id integer not null
		constraint cart_relation_company_company_id_fk
			references relation.company,
	address_id integer,
	relation_type text,
	contacts_json jsonb,
	constraint cart_relation_pk
		primary key (cart_id, company_id)
);

alter table cart_relation owner to xfw3;

