create table formula
(
	formula_id integer generated always as identity
		primary key,
	-- the name a formula is known by; every version of it shares the code
	formula_code text not null,
	formula_json jsonb not null,
	formula_level integer default 0 not null,
	version integer default 1 not null,
	version_status text default 'active'::text not null
		constraint formula_version_status_check
			check (version_status in ('draft', 'pending-approval', 'active', 'archived')),
	created_at timestamp with time zone default now() not null,
	unique (formula_code, version)
);

comment on table formula is 'Versioned formulas. One row per version of a code; the code is what the xbom refers to. Which version applies at a moment: the newest active or archived row created before it (catalog.get_formula). draft and pending-approval never apply.';
comment on column formula.version_status is 'draft -> pending-approval -> active -> archived. At most one active version per code; archived versions stay valid for what was created in their time.';
comment on column formula.created_at is 'The moment this version starts to apply. Set it when the version becomes active, not when the draft is typed.';

alter table formula owner to xfw3;

-- one active version per code
create unique index uq_formula_code_active
	on formula (formula_code)
	where (version_status = 'active');

-- the as-of lookup: newest applying version of a code before a moment
create index idx_formula_code_created
	on formula (formula_code, created_at desc)
	where (version_status IN ('active', 'archived'));
