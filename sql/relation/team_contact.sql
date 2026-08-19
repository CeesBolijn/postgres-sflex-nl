create table team_contact
(
	team_id integer not null
		constraint fk_team_contact_team
			references team
				on update cascade on delete cascade,
	contact_id integer not null
		constraint fk_team_contact_contact
			references contact
				on update cascade on delete cascade,
	constraint pk_team_contact
		primary key (team_id, contact_id)
);

comment on table team_contact is 'Assignment of contacts to teams.';

alter table team_contact owner to xfw3;

create index ix_team_contact_contact_id
	on team_contact (contact_id);

