create table pricing
(
	pricing_id integer generated always as identity
		constraint pk_relation_pricing
			primary key,
	company_group_id integer,
	item_code_pattern text,
	discount_formula_json jsonb,
	base_price_formula_json jsonb,
	item_code_pattern_len integer generated always as (length(item_code_pattern)) stored
);

alter table pricing owner to xfw3;

create index idx_relation_pricing_pattern
	on pricing (base_price_formula_json asc, discount_formula_json asc, item_code_pattern asc, item_code_pattern_len desc);

