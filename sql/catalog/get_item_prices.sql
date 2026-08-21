create function catalog.get_item_prices(p_item_codes text[], p_tenant_id integer, p_at timestamp with time zone DEFAULT now())
 RETURNS TABLE(item_code text, item_code_path ltree, price_tiers_json jsonb, consolidated_formula_json jsonb)
 LANGUAGE sql
 STABLE
AS $function$
    -- One row per item code: the base price tiers of the root tenant above
    -- p_tenant_id, plus the formula steps from that root down to p_tenant_id
    -- concatenated into one consolidated formula. Everything resolves as of
    -- p_at: the newest active or archived version created at or before that
    -- moment. Per chain level the most specific match on item_code_path
    -- applies; a level without a match changes nothing there;
    -- consolidated_formula_json is null when nothing matches at all (the
    -- tiers apply as-is). A tenant without parent_tenant_id is a root.
    with recursive chain as (
        -- from the requesting tenant up to the root; depth 0 = the tenant itself
        select t.tenant_id, t.parent_tenant_id, 0 as depth
        from site.tenant t
        where t.tenant_id = p_tenant_id
        union all
        select t.tenant_id, t.parent_tenant_id, c.depth + 1
        from chain c
        join site.tenant t on t.tenant_id = c.parent_tenant_id
    ),
    base as (
        -- applying version of the root tenant's price list per item code
        select distinct on (bp.item_code)
               bp.item_code, bp.item_code_path, bp.price_tiers_json
        from catalog.item_base_price bp
        where bp.item_code = any (p_item_codes)
          and bp.tenant_id = (select c.tenant_id from chain c
                              where c.parent_tenant_id is null)
          and bp.version_status in ('active', 'archived')
          and bp.created_at <= p_at
        order by bp.item_code, bp.created_at desc, bp.version desc
    ),
    applying as (
        -- applying formula version per scope per chain level
        select distinct on (c.depth, f.item_code_path)
               c.depth, f.item_code_path, f.formula_json
        from catalog.item_price_formula f
        join chain c on c.tenant_id = f.tenant_id
        where f.version_status in ('active', 'archived')
          and f.created_at <= p_at
        order by c.depth, f.item_code_path, f.created_at desc, f.version desc
    ),
    picked as (
        -- per item per chain level the most specific matching scope wins
        select distinct on (b.item_code, a.depth)
               b.item_code, a.depth, a.formula_json
        from base b
        join applying a on b.item_code_path <@ a.item_code_path
        order by b.item_code, a.depth, nlevel(a.item_code_path) desc
    )
    -- root side first: that is the order in which the tenants apply to each other
    select b.item_code, b.item_code_path, b.price_tiers_json,
           cons.consolidated_formula_json
    from base b
    left join (
        select p.item_code,
               jsonb_agg(s.step order by p.depth desc, s.ord) as consolidated_formula_json
        from picked p
        cross join lateral jsonb_array_elements(p.formula_json)
                           with ordinality as s(step, ord)
        group by p.item_code
    ) cons on cons.item_code = b.item_code;
$function$

alter function catalog.get_item_prices(p_item_codes text[], p_tenant_id integer, p_at timestamp with time zone) owner to xfw3;
