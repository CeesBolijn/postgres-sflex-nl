create table resource_item_profile
(
	resource_item_profile_id integer generated always as identity
		primary key,
	domain_id integer not null,
	resource_uid text not null
		references resource (resource_uid),
	item_codes text[],
	profile_state text[] not null,
	profile_name text,
	material_ids integer[],
	foreign key (domain_id, profile_name) references profile
);

alter table resource_item_profile owner to xfw3;

create index idx_resource_item_profile_name
	on resource_item_profile (profile_name);

create index idx_resource_item_profile_item_codes
	on resource_item_profile using gin (item_codes);

create index idx_resource_item_profile_state
	on resource_item_profile (profile_state);

