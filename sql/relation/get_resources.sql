create function get_resources(p_line_type text) returns TABLE(resource_uid text, resource_name text)
	language plpgsql
as $$
#variable_conflict use_column
BEGIN
  RETURN QUERY
  SELECT r.resource_uid, r.resource_name
  FROM   relation.resource r
  JOIN   relation.production_line pl ON pl.line_id = r.line_id
  JOIN   relation.lookup l ON l.lookup = 'lookup_step_category'
  JOIN   LATERAL jsonb_array_elements(l.lookup_json) AS el
         ON el->>'step' = r.step
  WHERE  pl.line_type = p_line_type
  ORDER  BY (el->>'order')::int, r.resource_name;
END;
$$;

alter function get_resources(text) owner to xfw3;

