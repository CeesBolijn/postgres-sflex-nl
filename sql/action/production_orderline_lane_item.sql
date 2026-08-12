create table production_orderline_lane_item
(
	production_orderline_id bigint not null,
	lane_item_id bigint not null,
	sort_order numeric,
	constraint production_orderline_lane_item_pk
		primary key (production_orderline_id, lane_item_id)
);

alter table production_orderline_lane_item owner to xfw3;

create index ix_production_orderline_lane_item_lane_item_id
	on production_orderline_lane_item (lane_item_id);

