create table profile
(
	domain_id integer not null,
	profile_name text not null,
	profile_json jsonb,
	active boolean,
	formula_id integer,
	primary key (domain_id, profile_name)
);

alter table profile owner to xfw3;

