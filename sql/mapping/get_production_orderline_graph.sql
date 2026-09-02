-- the line filter became an array, so the old signature has to go first
drop function if exists mapping.get_production_orderline_graph(timestamp with time zone, integer, integer, text[]);
-- the customer filter joined the signature, so the version in the database has to go too
drop function if exists mapping.get_production_orderline_graph(timestamp with time zone, integer[], integer, text[], integer);

create function mapping.get_production_orderline_graph(p_from timestamp with time zone DEFAULT CURRENT_DATE, p_production_line_ids integer[] DEFAULT NULL::integer[], p_domain_id integer DEFAULT 1, p_status_levels text[] DEFAULT NULL::text[], p_customer_id integer DEFAULT NULL::integer) returns TABLE(internal_status_code text, status_title text, regular_class_names jsonb, rework_class_names jsonb, orderline_status_sequence integer, total_orders bigint, total_product_amount numeric, total_sqm numeric, production_date date, total_nest_count integer, total_nest_sqm numeric, total_rework_count bigint, total_rework_amount numeric, total_rejected_amount numeric, total_rejected_sqm numeric, total_produced_amount numeric)
	stable
	language sql
as $$
    with detail as (
        -- look_back = 0 and look_ahead = 0: the graph always reports on exactly
        -- one logistics date, the viewed day.
        select *
        from mapping.get_production_orderline_detail(
            p_date               => p_from,
            p_date_type          => 'logistics',
            p_look_back_days     => 0,
            p_look_ahead_days    => 0,
            p_production_line_ids => p_production_line_ids,
            p_customer_id        => p_customer_id,
            -- filtered at the scan, not on the rows coming back
            p_status_levels      => p_status_levels,
            p_is_open            => true,
            p_domain_id          => p_domain_id
        ) d
    ),
    nest_status as (
        -- Distinct nests per status, with the balance in that status from
        -- nest_log. get_nest_status returns one row per (nest, status);
        -- step_category and internal_status share the same sequences.
        select ns.status_sequence                                   as orderline_status_sequence,
               count(distinct ns.nest_id)::integer                  as total_nest_count,
               sum(ns.current_amount * n.width * n.height)::numeric as total_nest_sqm
        from legacy.get_nest_status(
                 array(select distinct ne.nest_id
                       from detail d
                       cross join lateral unnest(d.nest_ids) as ne(nest_id))::bigint[],
                 p_domain_id) ns
        join legacy.nest n on n.nest_id = ns.nest_id
        group by ns.status_sequence
    ),
    grouped as (
        select d.internal_status_code,
               d.status_sequence as orderline_status_sequence,
               d.status_title,
               count(distinct d.production_order_id) as total_orders,
               sum(d.product_amount)                 as total_product_amount,
               sum(d.sqm)                            as total_sqm,
               min(d.production_date)                as production_date,
               -- rework on the orderline itself plus the reruns of its nests
               sum((d.impact_json ->> 'rework_count')::integer)::bigint           as total_rework_count,
               sum((d.impact_json ->> 'rework_amount')::numeric)                  as total_rework_amount,
               sum(d.rejected_amount)                                              as total_rejected_amount,
               -- Rejected sqm per orderline, using that orderline's own sqm per product.
               sum(d.sqm / nullif(d.product_amount, 0) * d.rejected_amount)        as total_rejected_sqm,
               sum(d.produced_amount)                                              as total_produced_amount
        from detail d
        group by d.internal_status_code, d.status_sequence, d.status_title
    )
    select
        g.internal_status_code,
        g.status_title,
        -- colour of the status lives in the lookup, not in code
        jsonb_build_array(si.class_name, 'segment-regular') as regular_class_names,
        jsonb_build_array(si.class_name, 'segment-rework')  as rework_class_names,
        g.orderline_status_sequence,
        g.total_orders,
        g.total_product_amount,
        g.total_sqm,
        g.production_date,
        ns.total_nest_count,
        ns.total_nest_sqm,
        g.total_rework_count,
        g.total_rework_amount,
        g.total_rejected_amount,
        g.total_rejected_sqm,
        g.total_produced_amount
    from grouped g
    left join mapping.internal_status si
           on si.code = g.internal_status_code and si.domain_id = p_domain_id
    left join nest_status ns
           on ns.orderline_status_sequence = g.orderline_status_sequence
    order by g.orderline_status_sequence;
$$;

alter function mapping.get_production_orderline_graph(timestamp with time zone, integer[], integer, text[], integer) owner to xfw3;

