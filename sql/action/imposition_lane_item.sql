-- Which impositions sit in a lane_item. Rows are written only where the set
-- changes: at the first step, and on a split or a merge. A lane_item without
-- rows carries the same impositions as the step before it (see
-- action.get_lane_item_impositions). Append-only: moved_at is the axis for
-- point-in-time reconstruction.
create table imposition_lane_item
(
	imposition_lane_item_id bigint generated always as identity
		primary key,
	lane_item_id bigint not null
		references lane_item,
	imposition_id bigint not null
		references production.imposition,
	moved_at timestamp with time zone default now() not null
);

comment on table imposition_lane_item is 'Membership of impositions in lane items, written on change only: first step, split, merge. No rows means: same set as the step before. Append-only.';

alter table imposition_lane_item owner to xfw3;

create index idx_imposition_lane_item_lane_item_id
	on imposition_lane_item (lane_item_id);

create index idx_imposition_lane_item_imposition_id
	on imposition_lane_item (imposition_id);
