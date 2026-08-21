create function catalog.get_formula(p_formula_codes text[], p_at timestamp with time zone DEFAULT now())
 RETURNS TABLE(formula_code text, formula_id integer, version integer, version_status text, created_at timestamp with time zone, formula_json jsonb, formula_level integer)
 LANGUAGE sql
 STABLE
AS $function$
    -- The version of each code that applies at p_at: the newest active or
    -- archived row created at or before that moment. Archived versions keep
    -- applying to what was made in their time; draft and pending-approval
    -- never apply. One row per code, none when no version applied yet at
    -- p_at. Ordered by level, lowest first, so the caller can evaluate them
    -- in that order.
    with applying as (
        select distinct on (f.formula_code)
               f.formula_code, f.formula_id, f.version, f.version_status,
               f.created_at, f.formula_json, f.formula_level
        from catalog.formula f
        where f.formula_code = any (p_formula_codes)
          and f.version_status in ('active', 'archived')
          and f.created_at <= p_at
        order by f.formula_code, f.created_at desc, f.version desc
    )
    select a.formula_code, a.formula_id, a.version, a.version_status,
           a.created_at, a.formula_json, a.formula_level
    from applying a
    order by a.formula_level, a.formula_code;
$function$

alter function catalog.get_formula(p_formula_codes text[], p_at timestamp with time zone) owner to xfw3;
