create table plan
(
	plan_id bigint generated always as identity
		primary key,
	step text not null,
	plan_date date not null,
	type text default 'material-resource-plan'::text not null,
	line_type text
);

alter table plan owner to xfw3;

