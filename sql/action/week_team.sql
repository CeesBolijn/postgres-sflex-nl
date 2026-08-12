create table week_team
(
	week integer not null,
	team_id integer not null,
	constraint week_team_pk
		primary key (team_id, week)
);

alter table week_team owner to xfw3;

