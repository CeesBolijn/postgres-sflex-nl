create table lane
(
	lane_id bigint generated always as identity
		primary key,
	plan_id bigint not null
		references plan
			on update cascade on delete cascade,
	sort_order numeric default 0 not null,
	-- a lane of a production plan is one or more interchangeable resources:
	-- their paths as they were when the plan was made (docs/resource-path.md);
	-- the first path is the primary one. Null on material lanes.
	resource_paths ltree[],
	unique (plan_id, sort_order)
);

comment on column lane.resource_paths is 'The resources this lane plans (relation.resource.resource_path), recorded at planning time; the first element is the primary one (display, tenant). Null for the material lanes of a material-resource-plan.';

alter table lane owner to xfw3;

create index idx_lane_resource_paths_gist
	on lane using gist (resource_paths gist__ltree_ops)
	where (resource_paths IS NOT NULL);
