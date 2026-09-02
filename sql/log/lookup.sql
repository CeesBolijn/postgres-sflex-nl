-- Same shape as relation.lookup. Holds the simplified flat lookups
-- (json/lookup/log/) while relation.lookup keeps the old nested form;
-- readers move over one by one and relation.lookup empties out.
create table lookup
(
	lookup text not null
		constraint pk_log_lookup
			primary key,
	lookup_json jsonb
);

alter table lookup owner to xfw3;
