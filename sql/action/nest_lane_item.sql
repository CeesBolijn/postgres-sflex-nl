create table nest_lane_item
(
	nest_id bigint not null,
	lane_item_id bigint not null,
	sort_order numeric,
	constraint nest_lane_item_pk
		primary key (nest_id, lane_item_id)
);

alter table nest_lane_item owner to xfw3;

create index ix_nest_lane_item_lane_item_id
	on nest_lane_item (lane_item_id);

