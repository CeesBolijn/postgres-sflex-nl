create table lane_item_dependency
(
	from_lane_item_id bigint not null
		references lane_item
			on delete cascade,
	to_lane_item_id bigint not null
		references lane_item
			on delete cascade,
	primary key (from_lane_item_id, to_lane_item_id)
);

alter table lane_item_dependency owner to xfw3;

create index lane_item_dependency_to_lane_item_id_idx
	on lane_item_dependency (to_lane_item_id);

