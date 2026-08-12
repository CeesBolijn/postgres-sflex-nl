create table internal_status
(
	internal_status_id integer not null
		primary key,
	domain_id integer not null,
	code varchar(100) not null,
	sequence integer,
	updated_at timestamp with time zone default CURRENT_TIMESTAMP,
	level text generated always as (
CASE
    WHEN (sequence >= 20000) THEN 'Sent'::text
    WHEN (sequence >= 921) THEN 'Logistics'::text
    WHEN (sequence = 920) THEN 'Internal transport'::text
    WHEN (sequence >= 649) THEN 'Production'::text
    WHEN (sequence < 649) THEN 'Pre-production'::text
    ELSE 'NA'::text
END) stored,
	internal_title text,
	group_name text,
	class_name text,
	i18n jsonb
);

alter table internal_status owner to xfw3;

create index idx_internal_status_code
	on internal_status (code);

create index idx_internal_status_code_sequence
	on internal_status (code, sequence);

