create table data_table
(
	data_table_id integer generated always as identity
		constraint unq_site_data_table_id
			unique,
	data_table text not null
		constraint pk_site_data_table
			primary key,
	query text,
	stored_proc text,
	description text not null,
	data_table_json jsonb,
	do_cache boolean not null,
	cache_cleanup text,
	cache_expired_time integer,
	forbidden_cache_param_keys jsonb default '["userContactId", "userCompanyId", "hostname", "userLanguage", "config"]'::jsonb not null
);

alter table data_table owner to xfw3;

create index idx_site_data_table_data_table
	on data_table (data_table);

