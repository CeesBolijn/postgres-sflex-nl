create table formula
(
	formula_id integer generated always as identity
		constraint pk_configurator_formula
			primary key,
	formula_name text,
	formula_json jsonb not null,
	formula_category text
);

alter table formula owner to xfw3;

create index idx_relation_formula_formula_id
	on formula (formula_id);

