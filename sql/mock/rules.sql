create table rules
(
	rule_id integer generated always as identity
		constraint pk_mock_rules
			primary key,
	rule_type text not null,
	rule_text text not null,
	created_at timestamp with time zone default CURRENT_TIMESTAMP
);

alter table rules owner to xfw3;

