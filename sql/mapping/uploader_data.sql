create table uploader_data
(
	uploader_data_id integer not null
		constraint pk_mapping_uploader_data
			primary key,
	domain_id integer,
	external_id integer,
	orderline_id integer,
	line_json jsonb,
	updated_at timestamp with time zone,
	file_amount integer default 1
);

alter table uploader_data owner to xfw3;

create index idx_uploader_data_orderline_id
	on uploader_data (orderline_id);

create index idx_uploader_data_updated_at
	on uploader_data (updated_at);

