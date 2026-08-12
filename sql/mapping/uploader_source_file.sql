create table uploader_source_file
(
	uploader_source_file_id bigint not null
		constraint pk_uploader_source_file
			primary key,
	uploader_data_id bigint not null,
	production_filename text,
	converted_preview_medium_url text,
	updated_at timestamp with time zone not null
);

alter table uploader_source_file owner to xfw3;

create index idx_uploader_source_file_production_filename
	on uploader_source_file (production_filename);

create index idx_uploader_source_file_uploader_data_id
	on uploader_source_file (uploader_data_id);

create index idx_uploader_source_file_updated_at
	on uploader_source_file (updated_at);

