create table lane
(
	lane_id bigint generated always as identity
		primary key,
	plan_id bigint not null
		references plan
			on update cascade on delete cascade,
	sort_order numeric default 0 not null,
	unique (plan_id, sort_order)
);

alter table lane owner to xfw3;

