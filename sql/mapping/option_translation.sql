create table option_translation
(
	option_translation_id serial
		primary key,
	option_codes text[],
	material_id integer,
	parent_title_base text,
	option_title_base text,
	ship_separately boolean,
	description text,
	option_set text,
	production_line_id integer,
	api_code text,
	product_api_code text
);

alter table option_translation owner to xfw3;

create unique index option_translation_product_api_code_api_code_uidx
	on option_translation (product_api_code, api_code)
	where ((product_api_code IS NOT NULL) AND (api_code IS NOT NULL));

