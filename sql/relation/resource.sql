create table resource
(
	resource_id integer generated always as identity
		constraint pk_relation_resource
			primary key,
	resource_json jsonb,
	company_id integer,
	active boolean default true,
	domain_id integer,
	x_bom_state_id integer,
	resource_uid text not null
		constraint uq_resource_uid
			unique,
	line_id integer,
	step text generated always as ((resource_json ->> 'step'::text)) stored,
	resource_name text generated always as ((resource_json ->> 'name'::text)) stored,
	resource_path ltree
);

comment on column resource.resource_path is 'Where the resource sits in the resource tree, coarse to specific: site.line_type.role.vendor.model.width.serial, e.g. dokkum.sheet.printer.durst.p5.350.32768. Labels are A-Za-z0-9_ only. resource_uid stays the stable key; the path is the classification and may change when a machine moves. Match with <@ / @>, most specific = highest nlevel().';

alter table resource owner to xfw3;

create index idx_relation_resource_uid
	on resource (resource_uid);

create index idx_relation_resource_step
	on resource (step);

create index idx_resource_pv2_id
	on resource ((resource_json ->> 'pv2_id'::text));

create unique index uq_resource_path
	on resource (resource_path)
	where (resource_path IS NOT NULL);

create index idx_resource_path_gist
	on resource using gist (resource_path);

