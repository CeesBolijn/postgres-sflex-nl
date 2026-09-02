-- The impositions that were actually made, per lane item. imposition_id is
-- for now an alias of legacy.nest.nest_id, the way imposition_group_id is an
-- alias of material_id; the move to production.imposition follows later
-- (see sql/action/planned/).
create table imposition_lane_item
(
	imposition_id bigint not null,
	lane_item_id bigint not null,
	sort_order numeric,
	constraint imposition_lane_item_pk
		primary key (imposition_id, lane_item_id)
);

alter table imposition_lane_item owner to xfw3;

create index ix_imposition_lane_item_lane_item_id
	on imposition_lane_item (lane_item_id);
