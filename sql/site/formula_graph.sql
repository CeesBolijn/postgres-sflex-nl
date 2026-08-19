create table formula_graph
(
	formula_graph_id integer generated always as identity
		constraint pk_site_formula_graph
			primary key,
	formula_graph_json jsonb default '{"nodes": [], "connections": []}'::jsonb not null,
	formula_graph_name text
		constraint formula_graph_pk
			unique
);

alter table formula_graph owner to xfw3;

