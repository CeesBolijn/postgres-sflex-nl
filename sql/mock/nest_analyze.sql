create table nest_analyze
(
	nest_analyze_id integer generated always as identity
		constraint pk_mock_nest_analyze
			primary key,
	nest_bucket_id integer
		constraint fk_nest_analyze_bucket
			references nest_bucket,
	nest_id integer,
	rule_id integer
		constraint fk_nest_analyze_rule
			references rules,
	current_ruling text,
	proposed_ruling text,
	trigger_metric text,
	trigger_threshold numeric,
	trigger_value numeric,
	analyze_json jsonb,
	remarks text,
	created_at timestamp with time zone default CURRENT_TIMESTAMP
);

alter table nest_analyze owner to xfw3;

