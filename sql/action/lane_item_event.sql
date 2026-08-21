create table lane_item_event
(
	lane_item_event_id bigint generated always as identity
		primary key,
	lane_item_id bigint not null
		references lane_item
			on delete cascade,
	status text not null,
	moved_at timestamp with time zone default now() not null
);

alter table lane_item_event owner to xfw3;

create index lane_item_event_lane_item_id_moved_at_idx
	on lane_item_event (lane_item_id asc, moved_at desc);

