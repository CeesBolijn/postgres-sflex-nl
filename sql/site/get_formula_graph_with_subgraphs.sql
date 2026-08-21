create function site.get_formula_graph_with_subgraphs(p_graph_id integer) returns TABLE(formula_graph_id integer, formula_graph_name text, formula_graph_json jsonb)
	language plpgsql
as $$
BEGIN
  RETURN QUERY
  SELECT 
    fg.formula_graph_id,
    fg.formula_graph_name,
    site.resolve_subgraphs(fg.formula_graph_json) as formula_graph_json
  FROM site.formula_graph fg
  WHERE fg.formula_graph_id = p_graph_id;
END;
$$;

alter function site.get_formula_graph_with_subgraphs(integer) owner to xfw3;

