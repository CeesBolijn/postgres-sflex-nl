create function get_production_orderline_aggregate(p_from timestamp with time zone DEFAULT CURRENT_DATE, p_date_type text DEFAULT 'logistics'::text, p_look_back_days integer DEFAULT NULL::integer, p_look_ahead_days integer DEFAULT NULL::integer, p_include_weekend boolean DEFAULT true, p_include_mandatory_dates boolean DEFAULT true, p_status_sequences integer[] DEFAULT NULL::integer[], p_batch_ids integer[] DEFAULT NULL::integer[], p_nest_ids bigint[] DEFAULT NULL::bigint[], p_production_line_id integer DEFAULT NULL::integer, p_material_ids integer[] DEFAULT NULL::integer[], p_is_open boolean DEFAULT true, p_waste_percentage numeric DEFAULT 20, p_threshold integer DEFAULT 1, p_domain_id integer DEFAULT 1) returns TABLE(material_id integer, material_name text, production_line_id integer, material_type text, orderline_count integer, product_amount numeric, sqm numeric, rework_count integer, rework_sqm numeric, rejected_amount numeric, produced_amount numeric, waste_percentage numeric, gross_sqm numeric, roll_meters numeric, panel_count integer, part_amount integer, status_json jsonb, part_status_json jsonb, nest_ids bigint[], delivery_class_names text[], nest_count integer, seconds_to_logistics_date integer, class_names text[], unit_class_names text[])
	stable
	language sql
as $$
    with detail as (
        select *
        from mapping.get_production_orderline_detail(
            p_from                    => p_from,
            p_date_type               => p_date_type,
            p_look_back_days          => p_look_back_days,
            p_look_ahead_days         => p_look_ahead_days,
            p_include_weekend         => p_include_weekend,
            p_include_mandatory_dates => p_include_mandatory_dates,
            p_status_sequences        => p_status_sequences,
            p_production_line_id      => p_production_line_id,
            p_material_ids            => p_material_ids,
            p_batch_ids               => p_batch_ids,
            p_nest_ids                => p_nest_ids,
            p_is_open                 => p_is_open,
            p_threshold               => p_threshold,
            p_domain_id               => p_domain_id
        )
    ),
    grouped as (
        select
            d.material_id,
            d.material_name,
            d.production_line_id,
            count(*)::integer           as orderline_count,
            sum(d.product_amount)       as product_amount,
            sum(d.sqm)                  as sqm,
            sum(d.rejected_amount)      as rejected_amount,
            sum(d.produced_amount)      as produced_amount,
            sum(d.part_amount)::integer as part_amount,
            -- own rework plus the number of reruns of the nests it sits on
            sum(coalesce((d.rework_json ->> 'count')::integer, 0)
              + coalesce((d.rework_json ->> 'nest_count')::integer, 0))::integer as rework_count,
            sum(coalesce((d.rework_json ->> 'sqm')::numeric, 0)
              + coalesce((d.rework_json ->> 'nest_sqm')::numeric, 0)) as rework_sqm,
            -- how much time the tightest orderline of the group still has
            floor(extract(epoch from (min(d.logistics_at)
                                      - (p_from at time zone 'Europe/Amsterdam'))))::integer
                as seconds_to_logistics_date
        from detail d
        group by d.material_id, d.material_name, d.production_line_id
    ),
    status as (
        -- how the orderlines are spread over their own status
        select s.material_id, s.production_line_id,
               jsonb_agg(jsonb_build_object(
                   'sequence',             s.status_sequence,
                   'internal_status_code', s.internal_status_code,
                   'class_names',          jsonb_build_array(si.class_name),
                   'i18n',                 si.i18n,
                   'title',                s.status_title,
                   'level',                s.status_level,
                   'orderline_count',      s.orderline_count,
                   'product_amount',       s.product_amount,
                   'sqm',                  s.sqm) order by s.status_sequence) as status_json
        from (
            select d.material_id, d.production_line_id, d.status_sequence,
                   d.internal_status_code, d.status_title, d.status_level,
                   count(*)::integer     as orderline_count,
                   sum(d.product_amount) as product_amount,
                   round(sum(d.sqm), 2)  as sqm
            from detail d
            group by d.material_id, d.production_line_id, d.status_sequence,
                     d.internal_status_code, d.status_title, d.status_level
        ) s
        -- colour and titles of the status live in the lookup, not in code
        left join mapping.internal_status si
               on si.code = s.internal_status_code and si.domain_id = p_domain_id
        group by s.material_id, s.production_line_id
    ),
    part as (
        -- how the product parts are spread over their status
        select p.material_id, p.production_line_id,
               jsonb_agg(jsonb_build_object(
                   'sequence',             p.sequence,
                   'internal_status_code', p.internal_status_code,
                   'class_names',          p.class_names,
                   'i18n',                 p.i18n,
                   'amount',               p.amount) order by p.sequence) as part_status_json
        from (
            select d.material_id, d.production_line_id,
                   (e.value ->> 'sequence')::integer              as sequence,
                   e.value ->> 'internal_status_code'             as internal_status_code,
                   e.value -> 'class_names'                       as class_names,
                   e.value -> 'i18n'                              as i18n,
                   round(sum((e.value ->> 'amount')::numeric), 2) as amount
            from detail d
            cross join lateral jsonb_array_elements(d.part_status_json) as e(value)
            group by d.material_id, d.production_line_id, 3, 4, 5, 6
        ) p
        group by p.material_id, p.production_line_id
    ),
    flag as (
        -- every marker and nest of the group, each one once
        select d.material_id, d.production_line_id,
               array_agg(distinct dc.name)   filter (where dc.name   is not null) as delivery_class_names,
               array_agg(distinct c.name)    filter (where c.name    is not null) as class_names,
               array_agg(distinct u.name)    filter (where u.name    is not null) as unit_class_names,
               array_agg(distinct n.nest_id) filter (where n.nest_id is not null) as nest_ids
        from detail d
        left join lateral unnest(d.delivery_class_names) as dc(name) on true
        left join lateral unnest(d.class_names)      as c(name)    on true
        left join lateral unnest(d.unit_class_names) as u(name)    on true
        left join lateral unnest(d.nest_ids)         as n(nest_id) on true
        group by d.material_id, d.production_line_id
    )
    select
        g.material_id,
        g.material_name,
        g.production_line_id,
        m.material_type,
        g.orderline_count,
        g.product_amount,
        round(g.sqm, 2),
        g.rework_count,
        round(g.rework_sqm, 2),
        round(g.rejected_amount, 2),
        round(g.produced_amount, 2),
        p_waste_percentage,
        c.gross_sqm,
        case when m.material_type = 'roll'
             then round(c.gross_sqm / nullif(m.roll_width, 0), 2) end,
        case when m.material_type = 'panel'
             then ceil(c.gross_sqm / nullif(m.panel_sqm, 0))::integer end,
        g.part_amount,
        coalesce(s.status_json, '[]'::jsonb),
        coalesce(pt.part_status_json, '[]'::jsonb),
        coalesce(f.nest_ids, '{}'::bigint[]),
        coalesce(f.delivery_class_names, '{}'::text[]),
        coalesce(array_length(f.nest_ids, 1), 0),
        g.seconds_to_logistics_date,
        coalesce(f.class_names, '{}'::text[]),
        coalesce(f.unit_class_names, '{}'::text[])
    from grouped g
    -- TODO: confirm the keys once line_json is known. Roll width in metres,
    -- panel size in metres.
    left join lateral (
        select mpl.line_json ->> 'material_type'          as material_type,
               (mpl.line_json ->> 'roll_width')::numeric   as roll_width,
               (mpl.line_json ->> 'panel_width')::numeric
             * (mpl.line_json ->> 'panel_height')::numeric as panel_sqm
        from mapping.material_production_line mpl
        where mpl.material_id        = g.material_id
          and mpl.production_line_id = g.production_line_id
    ) m on true
    left join status s on s.material_id = g.material_id and s.production_line_id = g.production_line_id
    left join part  pt on pt.material_id = g.material_id and pt.production_line_id = g.production_line_id
    left join flag   f on f.material_id = g.material_id and f.production_line_id = g.production_line_id
    cross join lateral (
        -- computed from the rounded values, so the column adds up with the
        -- sqm and rework_sqm shown next to it
        select round((round(g.sqm, 2) + round(g.rework_sqm, 2))
                     * (1 + p_waste_percentage / 100), 2) as gross_sqm
    ) c
    order by g.material_id, g.production_line_id;
$$;

alter function get_production_orderline_aggregate(timestamp with time zone, text, integer, integer, boolean, boolean, integer[], integer[], bigint[], integer, integer[], boolean, numeric, integer, integer) owner to xfw3;

