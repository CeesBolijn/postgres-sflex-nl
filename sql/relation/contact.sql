create table contact
(
	contact_id integer generated always as identity
		constraint pk_relation_contact
			primary key,
	password text,
	company_id integer
		constraint fk_relation_contact_company
			references company
				on delete cascade,
	language text default 'nl'::character varying not null,
	fallback_language text default 'en'::character varying,
	first_name text,
	insertion text,
	last_name text,
	birth_date date,
	gender integer default 0 not null,
	email text,
	phone text,
	mobile text,
	config jsonb default '{}'::jsonb not null,
	expire_date timestamp with time zone,
	abbreviation text,
	competences bigint,
	team_id integer,
	active boolean default true,
	created_date_time timestamp with time zone default CURRENT_TIMESTAMP,
	roles jsonb not null,
	verify text default gen_random_uuid()
);

alter table contact owner to xfw3;

