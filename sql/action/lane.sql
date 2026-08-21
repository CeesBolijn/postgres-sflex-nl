create table lane
(
	lane_id bigint generated always as identity
		primary key,
	-- the day this strip of time belongs to; the boards that show it, and
	-- their order per board, hang in plan_lane
	lane_date date not null,
	-- the machine this lane plans, wherever it physically stands: a foil plan
	-- can carry a printer standing in the sheet hall (plan_lane hangs the
	-- lane under both boards). Snapshot at planning time
	-- (docs/resource-path.md). Null on material lanes.
	resource_path ltree
);

comment on column lane.lane_date is 'The day of this strip of time. A lane is one machine-day (or material-day); which plans show it says plan_lane.';

comment on column lane.resource_path is 'The machine this lane plans (relation.resource.resource_path), recorded at planning time. The path holds the physical department, the plan holds the order side; plan_lane hangs the lane under both. Null for the material lanes of a material-resource-plan.';

alter table lane owner to xfw3;

-- one lane per machine per day
create unique index uq_lane_date_resource_path
	on lane (lane_date, resource_path)
	where (resource_path IS NOT NULL);

create index idx_lane_date
	on lane (lane_date);

create index idx_lane_resource_path_gist
	on lane using gist (resource_path)
	where (resource_path IS NOT NULL);
