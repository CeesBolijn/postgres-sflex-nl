create table material_resource_plan_lane
(
	lane_id bigint not null
		references action.lane
			on delete cascade,
	material_resource_plan_id bigint not null,
	primary key (lane_id, material_resource_plan_id)
);

alter table material_resource_plan_lane owner to xfw3;

create index material_resource_plan_lane_material_resource_plan_id_idx
	on material_resource_plan_lane (material_resource_plan_id);

