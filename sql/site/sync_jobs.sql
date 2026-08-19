create table sync_jobs
(
	sync_job_name text not null
		constraint pk_site_sync_jobs
			primary key,
	source_db text not null,
	query text not null,
	cron text default '0 */5 * * * *'::character varying not null,
	exec_data_table text not null,
	is_active boolean default true not null
);

alter table sync_jobs owner to xfw3;

