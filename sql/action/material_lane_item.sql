-- The material of a planned slot. On the item, not on the lane: a copied
-- slot takes its material along, and lane_item stays generic (pv2 machine
-- items carry no material). Same shape as nest_lane_item.
create table action.material_lane_item
(
	material_id integer not null,
	lane_item_id bigint not null
		references action.lane_item
			on delete cascade,
	constraint material_lane_item_pk
		primary key (material_id, lane_item_id)
);

alter table action.material_lane_item owner to xfw3;

create index ix_material_lane_item_lane_item_id
	on action.material_lane_item (lane_item_id);
