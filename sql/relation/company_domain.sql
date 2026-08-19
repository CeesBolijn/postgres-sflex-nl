create table company_domain
(
	company_id integer not null
		constraint fk_relation_company_domain_company
			references company
				on update cascade on delete cascade,
	domain_id integer not null,
	parent_company_id integer,
	domains text
);

alter table company_domain owner to xfw3;

create index idx_relation_company_domain_company_id
	on company_domain (company_id);

create index idx_relation_company_domain_domain_id
	on company_domain (domain_id);

create index idx_relation_company_domain_parent_company_id
	on company_domain (parent_company_id);

