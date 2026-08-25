-- Flat production-line list for select controls (the production board
-- filter). Return type changed twice, so the old signature goes first.
drop function if exists relation.get_production_lines();

create function relation.get_production_lines() returns TABLE(line_id integer, line text, i18n jsonb, line_type text)
	stable
	language plpgsql
as $$
#variable_conflict use_column
begin
    return query
    -- only real production lines: a line without line_type (Canvas, Supply,
    -- ONB, Not applicable, ...) is a bookkeeping row, never a filter choice
    select pl.line_id, pl.line, pl.line_json -> 'i18n', pl.line_type
    from relation.production_line pl
    where pl.line_type is not null
    order by pl.line;
end;
$$;

alter function relation.get_production_lines() owner to xfw3;
