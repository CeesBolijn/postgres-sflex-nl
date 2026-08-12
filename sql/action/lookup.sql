create table lookup
(
	lookup text not null
		constraint pk_action_lookup
			primary key,
	lookup_json jsonb
);

alter table lookup owner to xfw3;

