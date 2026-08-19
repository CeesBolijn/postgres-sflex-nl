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
	-- the planner pinned it: it keeps its offset when the lane is repacked
	is_pinned boolean default false not null,
	-- may not be split into two lane items
	no_split boolean default false not null,
	-- 0 = planned, 1 = realized (written from the logs, never by the board)
	level smallint default 0 not null
		constraint lane_item_level_check
			check (level in (0, 1)),
	-- where the item comes from, so the writer finds it again on an update:
	-- pv2 + plannable_item_id, or planner + its own ref
	source text,
	source_ref text,
	-- the order within a lane is unique, as the lane order is within a plan
	unique (lane_id, sort_order),
	constraint lane_item_source_ref_uq
		unique (source, source_ref)
);

comment on column lane_item.source is 'Who wrote the item: pv2 (crud_object), planner, log (level 1). Together with source_ref the upsert key.';
comment on column lane_item.source_ref is 'The id of the item at its source: pv2 plannable_item_id, ...';

comment on column lane_item.level is '0 = planned by the planner; 1 = realized, folded in from log.data / log.state. Same lane, same axis; the board renders them apart.';

comment on column lane_item.is_pinned is 'Pinned by the planner: keeps its start_offset_in_seconds when the lane is repacked; a Shift+drop on the board flips it.';
comment on column lane_item.no_split is 'The item may not be split into two lane items (was is_atomic on the old plan). Default false: splitting allowed.';

alter table lane_item owner to xfw3;

