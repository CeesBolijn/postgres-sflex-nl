create function catalog.get_formula(p_formula_codes text[], p_at timestamp with time zone DEFAULT now(), p_statuses text[] DEFAULT ARRAY['active'::text, 'archived'::text]) returns TABLE(formula_code text, formula_id integer, version integer, status text, created_at timestamp with time zone, formula_json jsonb, formula_level integer)
	stable
	language sql
as $$
    -- The version of each code that applies at p_at: the newest row created
    -- at or before that moment with a status in p_statuses. The default,
    -- active and archived, is what has ever applied: archived versions keep
    -- applying to what was made in their time; draft and pending-approval
    -- never do unless asked for (a preview). One row per code, none when no
    -- version applied yet at p_at. Ordered by level, lowest first, so the
    -- caller can evaluate them in that order.
    with applying as (
        select distinct on (f.formula_code)
               f.formula_code, f.formula_id, f.version, f.status, f.created_at,
               f.formula_json, f.formula_level
        from catalog.formula f
        where f.formula_code = any (p_formula_codes)
          and f.status = any (p_statuses)
          and f.created_at <= p_at
        order by f.formula_code, f.created_at desc, f.version desc
    )
    select a.formula_code, a.formula_id, a.version, a.status, a.created_at,
           a.formula_json, a.formula_level
    from applying a
    order by a.formula_level, a.formula_code;
$$;

alter function catalog.get_formula(text[], timestamp with time zone, text[]) owner to xfw3;
