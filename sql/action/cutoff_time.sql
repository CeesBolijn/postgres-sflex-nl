create table cutoff_time
(
	cutoff_time_id integer generated always as identity
		primary key,
	type text not null,
	code text not null,
	rule_path ltree not null,
	weekday smallint not null
		constraint cutoff_time_weekday_ck
			check ((weekday >= 1) AND (weekday <= 7)),
	cutoff_seconds integer not null
		constraint cutoff_time_seconds_ck
			check ((cutoff_seconds >= 0) AND (cutoff_seconds <= 86399)),
	moved_at timestamp with time zone default now() not null,
	moved_by text,
	constraint cutoff_time_version_uq
		unique (type, code, rule_path, weekday, moved_at)
);

comment on table cutoff_time is 'Append-only cutoff times. Newest moved_at per key wins. rule_path is an ltree drilldown path of ids: tenant, tenant.line, tenant.line.material. Most specific matching path wins.';

comment on column cutoff_time.rule_path is 'ltree id path, most specific level last (tenant.line.material). Not the resource tree of relation.resource.resource_path. A cutoff applies to everything under its path: match with <@, the winner is the deepest match (max nlevel(rule_path)).';

comment on column cutoff_time.cutoff_seconds is 'Seconds since local midnight. Values above 86399 mean the following day.';

alter table cutoff_time owner to xfw3;

create index cutoff_time_lookup_idx
	on cutoff_time (type collate "C" asc, code collate "C" asc, rule_path asc, weekday asc, moved_at desc) include (cutoff_seconds);

create index cutoff_time_rule_path_gist
	on cutoff_time using gist (rule_path);

