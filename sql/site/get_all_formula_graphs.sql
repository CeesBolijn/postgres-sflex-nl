create function get_all_formula_graphs() returns TABLE(formula_graph_id integer, formula_graph_name character varying)
	language plpgsql
as $$
BEGIN
    RETURN QUERY
    SELECT
        formula_graph.formula_graph_id,
        formula_graph.formula_graph_name
    FROM site.formula_graph
    WHERE formula_graph.formula_graph_name IS NOT NULL;
END;
$$;

alter function get_all_formula_graphs() owner to xfw3;

