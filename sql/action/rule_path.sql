-- Predicate for "all matches" mode. A scope entry without a trailing dot
-- matches that exact path; a scope entry ending in a dot matches its
-- direct children only.
create or replace function action.rule_path_matches(
  entry_rule_path  text,
  scope_rule_paths text[]
)
returns boolean
language sql
immutable
parallel safe
strict
as $$
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

alter function action.rule_path_matches(text, text[]) owner to xfw3;

-- Returns every ancestor path plus the path itself, shortest first.
-- Used for "best match" mode. A trailing dot is meaningless here and
-- is stripped.
create or replace function action.rule_path_ancestors(entry_rule_path text)
returns text[]
language sql
immutable
parallel safe
strict
as $$
  with parts as (
    select string_to_array(rtrim(entry_rule_path, '.'), '.') as part
  )
  select array_agg(array_to_string(part[1:i], '.') order by i)
  from parts, generate_subscripts(part, 1) as i;
$$;

alter function action.rule_path_ancestors(text) owner to xfw3;

-- Usage:

-- all matches
-- select * from mapping.some_table as r
-- where action.rule_path_matches(r.rule_path, '{1,1.5.}');

-- best match — order by real depth, not string length
-- (length() breaks on e.g. '1.10' vs '1.5.3': same length, different depth)
-- select * from mapping.some_table as r
-- where r.rule_path = any (action.rule_path_ancestors('1.4.6'))
-- order by array_length(string_to_array(r.rule_path, '.'), 1) desc
-- limit 1;

-- Both functions are immutable and table-agnostic, usable on any table
-- with a rule_path column, and can be used in an expression index if
-- the best-match query ever becomes a hot path.

-- Note: these text-based functions predate the ltree columns. Since
-- 2026-08-18 relation.resource.resource_path and action.cutoff_time.rule_path
-- are ltree: there use <@ / @> and nlevel() instead of these functions.
-- non_working_times.rule_path is still text and still uses them. Recommended:
-- add a per-table CHECK constraint since ltree's format validation is
-- lost, e.g.:
--   alter table mapping.some_table
--     add constraint some_table_rule_path_format
--     check (rule_path ~ '^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)*$');
