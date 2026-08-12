create table planning
(
	planning_id bigint generated always as identity
		primary key,
	action_id bigint,
	planning_json jsonb not null
);

alter table planning owner to xfw3;

