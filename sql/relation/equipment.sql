create table equipment
(
	equipment_id integer generated always as identity
		constraint pk_relation_equipment
			primary key,
	equipment_json jsonb,
	company_id integer,
	type_json text,
	active boolean default true
);

alter table equipment owner to xfw3;

