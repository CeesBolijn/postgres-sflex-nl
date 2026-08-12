create table lane_item
(
	lane_item_id bigint generated always as identity
		primary key,
	lane_id bigint not null
		references lane,
	sort_order numeric not null,
	start_offset_in_seconds integer
		constraint lane_item_start_offset_in_seconds_check
			check ((start_offset_in_seconds >= 0) AND (start_offset_in_seconds <= 86399)),
	duration_in_seconds integer default 0 not null
		constraint lane_item_duration_in_seconds_check
			check (duration_in_seconds >= 0),
	is_fixed_group text,
	is_pinned integer,
	unique (lane_id, sort_order)
);

alter table lane_item owner to xfw3;

