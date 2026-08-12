create table material_print_schedule
(
	material_id integer,
	material_code text,
	line text not null,
	material_name text not null,
	interval_days integer,
	interval_start_date date,
	delivery_hours integer,
	resource_uids jsonb,
	valid_resources_json jsonb,
	production_line_id integer,
	is_manualy_set boolean default false not null,
	nest_moment_codes text[],
	tenant_id integer,
	min_delivery_hours integer
);

alter table material_print_schedule owner to xfw3;

create index ix_material_print_schedule_material_id
	on material_print_schedule (material_id);

