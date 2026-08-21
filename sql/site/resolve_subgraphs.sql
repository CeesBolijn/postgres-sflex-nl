create function site.resolve_subgraphs(p_graph_json jsonb, p_depth integer DEFAULT 0, p_max_depth integer DEFAULT 10) returns jsonb
	language plpgsql
as $$
DECLARE
  v_resolved_json JSONB;
BEGIN
  -- Safety check to prevent infinite recursion
  IF p_depth >= p_max_depth THEN
    RETURN p_graph_json;
  END IF;

  -- Process all nodes and resolve subgraphs
  SELECT jsonb_set(
    p_graph_json,
    '{nodes}',
    (
      SELECT jsonb_agg(
        CASE 
          WHEN node->>'type' = 'subgraph' THEN
            node || jsonb_build_object(
              'subgraph',
              site.resolve_subgraphs(
                (
                  SELECT formula_graph_json
                  FROM site.formula_graph
                  WHERE formula_graph_id = (node->>'graphId')::int
                ),
                p_depth + 1,
                p_max_depth
              )
            )
          ELSE node
        END
      )
      FROM jsonb_array_elements(p_graph_json->'nodes') as node
    )
  ) INTO v_resolved_json;

  RETURN v_resolved_json;
END;
$$;

alter function site.resolve_subgraphs(jsonb, integer, integer) owner to xfw3;

