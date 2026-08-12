create table line_item_resource
(
	line_item_resource_id bigint generated always as identity
		primary key,
	line_item_id bigint not null
		references line_item,
	kind text default 'narrow'::text not null
		constraint line_item_resource_kind_check
			check (kind = ANY (ARRAY['narrow'::text, 'commit'::text, 'revert'::text, 'force'::text])),
	resource_uids text[] not null,
	reason text,
	updated_at timestamp with time zone default now() not null,
	constraint force_requires_reason
		check ((kind <> 'force'::text) OR (reason IS NOT NULL))
);

alter table line_item_resource owner to xfw3;

