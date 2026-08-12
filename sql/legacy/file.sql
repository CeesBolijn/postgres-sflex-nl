create table file
(
	file_uid uuid not null
		constraint pk_production_file
			primary key,
	file_json jsonb default '{"data": {}, "path": "", "schema": "production", "imgPath": "", "fileName": "", "extension": "", "thumbPath": "", "imgAndThumbs": [{"imgFileName": "", "thumbFileName": ""}], "imgExtension": "", "thumbExtension": ""}'::jsonb not null,
	file_date_time timestamp with time zone default CURRENT_TIMESTAMP
);

alter table file owner to xfw3;

create index idx_production_file_file_uid
	on file (file_uid);

