create table material_production_line
(
	material_production_line_id integer generated always as identity
		constraint pk_mapping_material_production_line
			primary key,
	domain_id integer,
	material_id integer,
	production_line_id integer,
	line_json jsonb,
	nesting_queue_guid uuid generated always as (
CASE
    WHEN ((line_json ->> 'substrate_name'::text) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'::text) THEN ((line_json ->> 'substrate_name'::text))::uuid
    ELSE NULL::uuid
END) stored,
	material_name text generated always as ((line_json ->> 'material_name'::text)) stored,
	is_active boolean,
	constraint uq_material_production_line
		unique (material_id, production_line_id)
);

alter table material_production_line owner to xfw3;

create index ix_material_production_line_material_id
	on material_production_line (material_id);

create index ix_material_production_line_production_line_id
	on material_production_line (production_line_id);

create index idx_material_production_line_material_id
	on material_production_line (material_id);

