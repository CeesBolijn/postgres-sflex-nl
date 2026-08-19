create table company
(
	company_id integer generated always as identity
		constraint pk_relation_company
			primary key,
	company_name text not null,
	relation_code text,
	config jsonb default '{}'::jsonb,
	website text,
	invoice_email text,
	payment_term integer default 14 not null,
	is_anonymous_domain_account_store boolean default false not null,
	company_email text,
	company_phone text,
	chamber_of_commerce text,
	vat_id text,
	active boolean default true,
	abb text,
	iban text,
	ai_context text default '{}'::text,
	remarks text
);

alter table company owner to xfw3;

