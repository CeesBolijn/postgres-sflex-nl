create function rule_path_matches(entry_rule_path text, scope_rule_paths text[]) returns boolean
	immutable
	strict
	parallel safe
	language sql
as $$
  -- a scope entry without a trailing dot matches that exact path;
  -- a scope entry ending in a dot matches its direct children only
  select exists (
    select 1
    from unnest(scope_rule_paths) as scope_rule_path
    where case
      when right(scope_rule_path, 1) = '.' then
             left(entry_rule_path, length(scope_rule_path)) = scope_rule_path
         and length(entry_rule_path) > length(scope_rule_path)
         and strpos(substr(entry_rule_path, length(scope_rule_path) + 1), '.') = 0
      else
        entry_rule_path = scope_rule_path
    end
  );
$$;

alter function rule_path_matches(text, text[]) owner to xfw3;

