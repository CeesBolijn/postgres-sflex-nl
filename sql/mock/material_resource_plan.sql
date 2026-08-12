create table material_resource_plan
(
	material_resource_plan_id bigint generated always as identity
		primary key,
	weekday smallint not null
		constraint material_resource_plan_weekday_check
			check ((weekday >= 1) AND (weekday <= 7)),
	step text not null,
	resource_uid text,
	sort_order numeric not null
		constraint material_resource_plan_sort_order_check
			check (sort_order >= (0)::numeric),
	material_id integer,
	next_start_offset_in_seconds integer default 0 not null,
	moved_at timestamp with time zone default now() not null,
	occurence integer default 0 not null,
	production_line_id integer,
	tenant_id integer,
	start_offset_in_seconds integer,
	is_pinned boolean
);

alter table material_resource_plan owner to xfw3;

create index ix_material_resource_plan_lane
	on material_resource_plan (weekday asc, step asc, resource_uid asc, sort_order asc, moved_at desc);

