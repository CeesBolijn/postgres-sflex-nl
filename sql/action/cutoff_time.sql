create table cutoff_time
(
	cutoff_time_id integer generated always as identity
		primary key,
	type text not null,
	code text not null,
	rule_path text not null
		constraint cutoff_time_path_ck
			check (rule_path ~ '^[0-9]+(\.[0-9]+)*$'::text),
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

comment on table cutoff_time is 'Append-only cutoff times. Newest moved_at per key wins. rule_path is a drilldown path: tenant, tenant.line, tenant.line.material. Most specific matching path wins.';

comment on column cutoff_time.rule_path is 'Dot-separated id path, most specific level last. Match with equality only, never with LIKE or a prefix operator.';

comment on column cutoff_time.cutoff_seconds is 'Seconds since local midnight. Values above 86399 mean the following day.';

alter table cutoff_time owner to xfw3;

create index cutoff_time_lookup_idx
	on cutoff_time (type collate "C" asc, code collate "C" asc, rule_path collate "C" asc, weekday asc, moved_at desc) include (cutoff_seconds);

