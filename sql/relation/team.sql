create table team
(
	team_id integer generated always as identity
		constraint pk_team
			primary key,
	parent_team_id integer
		constraint fk_team_parent_team
			references team
				on update cascade on delete restrict,
	description text not null,
	production_line_id integer,
	tenant_id integer,
	steps text[],
	constraint ck_team_no_self_parent
		check (parent_team_id IS DISTINCT FROM team_id)
);

comment on table team is 'Teams, optionally nested through parent_team_id.';

comment on column team.parent_team_id is 'Parent team; NULL marks a root team.';

alter table team owner to xfw3;

create index ix_team_parent_team_id
	on team (parent_team_id);

am_id)
);

comment on table relation.team is 'Teams, optionally nested through parent_team_id.';
comment on column relation.team.parent_team_id is 'Parent team; NULL marks a root team.';

alter table relation.team owner to xfw3;

create index ix_team_parent_team_id on relation.team (parent_team_id);

-- Which team is active in which ISO week, used to resolve the team segment
-- of a rule_path for a given plan date.
create table action.week_team
(
    week    integer not null,
    team_id integer not null,
    constraint week_team_pk
        primary key (team_id, week)
);

alter table action.week_team owner to xfw3;

-- Notes:
-- - relation.team_contact (many-to-many teams <-> contacts) was proposed
--   earlier in the same design but not re-confirmed in the final version:
--
--   CREATE TABLE relation.team_contact (
--       team_id     integer NOT NULL,
--       contact_id  integer NOT NULL,
--       CONSTRAINT pk_team_contact PRIMARY KEY (team_id, contact_id),
--       CONSTRAINT fk_team_contact_team FOREIGN KEY (team_id)
--           REFERENCES relation.team (team_id) ON UPDATE CASCADE ON DELETE CASCADE,
--       CONSTRAINT fk_team_contact_contact FOREIGN KEY (contact_id)
--           REFERENCES relation.contact (contact_id) ON UPDATE CASCADE ON DELETE CASCADE
--   );
--   ALTER TABLE relation.team_contact OWNER TO xfw3;
--   CREATE INDEX ix_team_contact_contact_id ON relation.team_contact (contact_id);
--
--   Check if still needed before creating it.
-- - cycle detection (A -> B -> A) is NOT covered by the check constraint;
--   needs a trigger or CRUD-function validation if that matters.
-- - rule_path for non_working_times: tenant_id.production_line_id.team_id,
--   with the team resolved via action.week_team for the plan's ISO week.
