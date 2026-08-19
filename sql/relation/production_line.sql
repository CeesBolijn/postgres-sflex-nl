create table production_line
(
	line_id integer not null
		constraint pk_relation_production_line
			primary key,
	line text,
	line_json jsonb,
	domain_id integer,
	model text,
	line_type text,
	tenant_id integer
);

alter table production_line owner to xfw3;

create index idx_production_line_line_id_type
	on production_line (line_id, line_type);

