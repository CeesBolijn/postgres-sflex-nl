create function rule_path_ancestors(entry_rule_path text) returns text[]
	immutable
	strict
	parallel safe
	language sql
as $$
  -- returns every ancestor path plus the path itself, shortest first;
  -- a trailing dot is meaningless here and is stripped
  with parts as (
    select string_to_array(rtrim(entry_rule_path, '.'), '.') as part
  )
  select array_agg(array_to_string(part[1:i], '.') order by i)
  from parts, generate_subscripts(part, 1) as i;
$$;

alter function rule_path_ancestors(text) owner to xfw3;

