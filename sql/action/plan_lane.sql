create table plan_lane
(
	plan_id bigint not null
		references plan
			on delete cascade,
	lane_id bigint not null
		references lane
			on delete cascade,
	sort_order numeric default 0 not null,
	primary key (plan_id, lane_id),
	unique (plan_id, sort_order)
);

comment on table plan_lane is 'Which boards (plans) show a lane, and in which order per board. A machine-day lane hangs under the order-side plan and the physical department''s plan, so both boards see its full occupation.';

alter table plan_lane owner to xfw3;

create index idx_plan_lane_lane_id
	on plan_lane (lane_id);
