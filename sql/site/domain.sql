create table domain
(
	domain_id integer generated always as identity
		constraint pk_site_domain
			primary key,
	domain_name text,
	contact_mail text,
	mail_domain text,
	domain_urls jsonb default '[{"language": "NL", "rootPath": "/", "domainUrl": "example.com"}]'::jsonb not null,
	website_config jsonb default '{}'::jsonb not null,
	service_config jsonb default '{}'::jsonb
);

alter table domain owner to xfw3;

create index idx_site_domain_domain_id
	on domain (domain_id);

