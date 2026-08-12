create table library_collection
(
	collection_id integer generated always as identity
		constraint library_collection_pk
			primary key,
	library_id integer,
	collection text,
	created_at timestamp with time zone default now() not null
);

alter table library_collection owner to xfw3;

