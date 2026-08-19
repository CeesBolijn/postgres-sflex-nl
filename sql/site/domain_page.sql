create table domain_page
(
	domain_id integer not null
		references domain,
	page_id integer not null
		references page,
	primary key (domain_id, page_id)
);

alter table domain_page owner to xfw3;

