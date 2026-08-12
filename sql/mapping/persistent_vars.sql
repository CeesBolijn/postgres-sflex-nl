create table persistent_vars
(
	key text not null
		constraint pk_probo_hub_persistent_vars
			primary key,
	value text
);

alter table persistent_vars owner to xfw3;

