-- return type changes, so the old signature has to go first
drop function if exists mapping.get_production_orderline_aggregate(timestamp with time zone, text, integer, integer, boolean, boolean, integer[], integer[], bigint[], integer, integer[], integer[], boolean, numeric, integer, integer);
drop function if exists mapping.get_production_orderline_aggregate(timestamp with time zone, text, integer, integer, boolean, boolean, integer[], text[], integer[], bigint[], integer, integer[], integer[], boolean, numeric, integer, integer);

create function mapping.get_production_orderline_aggregate(p_from timestamp with time zone DEFAULT CURRENT_DATE, p_date_type text DEFAULT 'logistics'::text, p_look_back_days integer DEFAULT NULL::integer, p_look_ahead_days integer DEFAULT NULL::integer, p_include_weekend boolean DEFAULT true, p_include_mandatory_days_off boolean DEFAULT true, p_status_sequences integer[] DEFAULT NULL::integer[], p_status_levels text[] DEFAULT NULL::text[], p_batch_ids integer[] DEFAULT NULL::integer[], p_nest_ids bigint[] DEFAULT NULL::bigint[], p_production_line_id integer DEFAULT NULL::integer, p_material_ids integer[] DEFAULT NULL::integer[], p_tenant_ids integer[] DEFAULT NULL::integer[], p_is_open boolean DEFAULT true, p_waste_percentage numeric DEFAULT 20, p_threshold integer DEFAULT 1, p_domain_id integer DEFAULT 1) returns TABLE(material_id integer, material_name text, production_line_id integer, delivery_hours integer, material_media_type_id integer, orderline_count integer, product_amount numeric, part_amount integer, amount numeric, sqm numeric, forecast_sqm numeric, rework_count integer, rework_sqm numeric, impact_json jsonb, rejected_amount numeric, produced_amount numeric, waste_percentage numeric, gross_sqm numeric, specs_json jsonb, status_json jsonb, part_status_json jsonb, nest_ids bigint[], delivery_class_names text[], nest_count integer, seconds_to_logistics_date integer, class_names text[], unit_class_names text[])
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
            p_include_mandatory_days_off => p_include_mandatory_days_off,
            p_tenant_ids              => p_tenant_ids,
            p_status_sequences        => p_status_sequences,
            p_status_levels           => p_status_levels,
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
            d.delivery_hours,
            count(*)::integer           as orderline_count,
            sum(d.product_amount)       as product_amount,
            sum(d.part_amount)::integer as part_amount,
            -- per orderline the parts when there are more of them than products
            sum(greatest(d.part_amount, d.product_amount)) as amount,
            sum(d.sqm)                  as sqm,
            sum(d.rejected_amount)      as rejected_amount,
            sum(d.produced_amount)      as produced_amount,
            -- own rework plus the number of reruns of the nests it sits on
            sum((d.impact_json ->> 'rework_count')::integer)  as rework_count,
            sum((d.impact_json ->> 'rework_amount')::numeric) as rework_amount,
            sum((d.impact_json ->> 'rework_sqm')::numeric)    as rework_sqm,
            -- how much time the tightest orderline of the group still has
            floor(extract(epoch from (min(d.logistics_at)
                                      - (p_from at time zone 'Europe/Amsterdam'))))::integer
                as seconds_to_logistics_date
        from detail d
        group by d.material_id, d.material_name, d.production_line_id, d.delivery_hours
    ),
    -- The days the detail looks at; a batch or nest scope has no window and
    -- takes the day of p_from. min() over the zero-or-one row of the helper.
    forecast_window as (
        select coalesce(min(w.from_date),  (p_from at time zone 'Europe/Amsterdam')::date)     as from_date,
               coalesce(min(w.until_date), (p_from at time zone 'Europe/Amsterdam')::date + 1) as until_date
        from action.get_date_window(
                 p_from,
                 case when p_batch_ids is null and p_nest_ids is null then p_look_back_days  end,
                 case when p_batch_ids is null and p_nest_ids is null then p_look_ahead_days end,
                 p_include_weekend, p_include_mandatory_days_off, p_tenant_ids) w
    ),
    -- p_tenant_ids narrows the forecast to the production companies of those
    -- tenants; nothing else in this function reads it.
    forecast as (
        select f.material_id, f.production_line_id,
               sum(f.forecast_sqm) as forecast_sqm
        from log.production_forecast_material f
        cross join forecast_window win
        where f.date >= win.from_date and f.date < win.until_date
          and (p_production_line_id is null or f.production_line_id = p_production_line_id)
          and (p_material_ids is null or f.material_id = any (p_material_ids))
          and (p_tenant_ids is null or f.production_company_id in (
                   select (v.value ->> 'production_company_id')::integer
                   from relation.lookup lk
                   cross join lateral jsonb_array_elements(lk.lookup_json) as v(value)
                   where lk.lookup = 'lookup_tenants'
                     and (v.value ->> 'tenant_id')::integer = any (p_tenant_ids)))
        group by f.material_id, f.production_line_id
    ),
    -- A material with a forecast but no open orderlines still gets a row
    -- (delivery_hours null). The forecast is per material and line: with
    -- inflow it is split over the delivery-hours groups pro rata to their
    -- sqm; without sqm anywhere it goes to the longest delivery time.
    combined as (
        select coalesce(g.material_id, fc.material_id)                 as material_id,
               coalesce(g.production_line_id, fc.production_line_id)   as production_line_id,
               g.delivery_hours,
               g.material_name,
               coalesce(g.orderline_count, 0)                          as orderline_count,
               coalesce(g.product_amount, 0)                           as product_amount,
               coalesce(g.part_amount, 0)                              as part_amount,
               coalesce(g.amount, 0)                                   as amount,
               coalesce(g.sqm, 0)                                      as sqm,
               case when g.material_id is null then fc.forecast_sqm
                    when sum(g.sqm) over w > 0
                         then fc.forecast_sqm * g.sqm / sum(g.sqm) over w
                    when g.delivery_hours is not distinct from max(g.delivery_hours) over w
                         then fc.forecast_sqm
                    else 0
               end                                                     as forecast_sqm,
               coalesce(g.rework_count, 0)                             as rework_count,
               coalesce(g.rework_amount, 0)                            as rework_amount,
               coalesce(g.rework_sqm, 0)                               as rework_sqm,
               coalesce(g.rejected_amount, 0)                          as rejected_amount,
               coalesce(g.produced_amount, 0)                          as produced_amount,
               g.seconds_to_logistics_date
        from grouped g
        full join forecast fc on fc.material_id = g.material_id and fc.production_line_id = g.production_line_id
        window w as (partition by g.material_id, g.production_line_id)
    ),
    status as (
        -- how the orderlines are spread over their own status
        select s.material_id, s.production_line_id, s.delivery_hours,
               jsonb_agg(jsonb_build_object(
                   'sequence',             s.status_sequence,
                   'internal_status_code', s.internal_status_code,
                   'class_names',          to_jsonb(array_remove(array[si.class_name], null)),
                   'i18n',                 si.i18n,
                   'title',                s.status_title,
                   'level',                s.status_level,
                   'orderline_count',      s.orderline_count,
                   'product_amount',       s.product_amount,
                   'sqm',                  s.sqm) order by s.status_sequence) as status_json
        from (
            select d.material_id, d.production_line_id, d.delivery_hours, d.status_sequence,
                   d.internal_status_code, d.status_title, d.status_level,
                   count(*)::integer     as orderline_count,
                   sum(d.product_amount) as product_amount,
                   round(sum(d.sqm), 2)  as sqm
            from detail d
            group by d.material_id, d.production_line_id, d.delivery_hours, d.status_sequence,
                     d.internal_status_code, d.status_title, d.status_level
        ) s
        -- colour and titles of the status live in the lookup, not in code
        left join mapping.internal_status si
               on si.code = s.internal_status_code and si.domain_id = p_domain_id
        group by s.material_id, s.production_line_id, s.delivery_hours
    ),
    part as (
        -- how the product parts are spread over their status
        select p.material_id, p.production_line_id, p.delivery_hours,
               jsonb_agg(jsonb_build_object(
                   'sequence',             p.sequence,
                   'internal_status_code', p.internal_status_code,
                   'class_names',          p.class_names,
                   'i18n',                 p.i18n,
                   'amount',               p.amount) order by p.sequence) as part_status_json
        from (
            select d.material_id, d.production_line_id, d.delivery_hours,
                   (e.value ->> 'sequence')::integer              as sequence,
                   e.value ->> 'internal_status_code'             as internal_status_code,
                   e.value -> 'class_names'                       as class_names,
                   e.value -> 'i18n'                              as i18n,
                   round(sum((e.value ->> 'amount')::numeric), 2) as amount
            from detail d
            cross join lateral jsonb_array_elements(d.part_status_json) as e(value)
            group by d.material_id, d.production_line_id, d.delivery_hours, 4, 5, 6, 7
        ) p
        group by p.material_id, p.production_line_id, p.delivery_hours
    ),
    flag as (
        -- every marker and nest of the group, each one once. One unnest per
        -- array, summed per group: joining the four unnests side by side
        -- multiplies the row estimate (1000 x 10 x 10 x 10 x 10), which drove
        -- the plan cost past the JIT thresholds and cost seconds per call.
        select k.material_id, k.production_line_id, k.delivery_hours,
               (select array_agg(distinct x order by x) from detail d, unnest(d.delivery_class_names) x
                 where d.material_id = k.material_id and d.production_line_id = k.production_line_id and d.delivery_hours is not distinct from k.delivery_hours) as delivery_class_names,
               (select array_agg(distinct x order by x) from detail d, unnest(d.class_names) x
                 where d.material_id = k.material_id and d.production_line_id = k.production_line_id and d.delivery_hours is not distinct from k.delivery_hours) as class_names,
               (select array_agg(distinct x order by x) from detail d, unnest(d.unit_class_names) x
                 where d.material_id = k.material_id and d.production_line_id = k.production_line_id and d.delivery_hours is not distinct from k.delivery_hours) as unit_class_names,
               (select array_agg(distinct x order by x) from detail d, unnest(d.nest_ids) x
                 where d.material_id = k.material_id and d.production_line_id = k.production_line_id and d.delivery_hours is not distinct from k.delivery_hours) as nest_ids
        from (select distinct d.material_id, d.production_line_id, d.delivery_hours from detail d) k
    )
    select
        g.material_id,
        coalesce(g.material_name, m.material_name),
        g.production_line_id,
        g.delivery_hours,
        m.material_media_type_id,
        g.orderline_count,
        g.product_amount,
        g.part_amount,
        g.amount,
        round(g.sqm, 2),
        round(g.forecast_sqm, 2),
        g.rework_count,
        round(g.rework_sqm, 2),
        -- the same shape as on the orderline, summed over the group
        jsonb_build_object(
            'count',         g.orderline_count,
            'amount',        g.product_amount,
            'sqm',           round(g.sqm, 2),
            'rework_count',  g.rework_count,
            'rework_amount', g.rework_amount,
            'rework_sqm',    round(g.rework_sqm, 2)),
        round(g.rejected_amount, 2),
        round(g.produced_amount, 2),
        p_waste_percentage,
        c.gross_sqm,
        -- one entry per size of the material, with what the gross sqm needs of
        -- it: sheets for a sheet material, metres for a roll; sizes are in cm
        (select coalesce(jsonb_agg(sp.value || jsonb_build_object('amount',
                    case m.material_media_type_id
                         when 1 then ceil(c.gross_sqm / nullif((sp.value ->> 'width')::numeric
                                                             * (sp.value ->> 'height')::numeric / 10000, 0))
                         when 3 then ceil(c.gross_sqm / nullif((sp.value ->> 'width')::numeric / 100, 0))
                    end) order by sp.ord), '[]'::jsonb)
         from jsonb_array_elements(m.specs) with ordinality as sp(value, ord)),
        coalesce(s.status_json, '[]'::jsonb),
        coalesce(pt.part_status_json, '[]'::jsonb),
        coalesce(f.nest_ids, '{}'::bigint[]),
        coalesce(f.delivery_class_names, '{}'::text[]),
        coalesce(array_length(f.nest_ids, 1), 0),
        g.seconds_to_logistics_date,
        coalesce(f.class_names, '{}'::text[]),
        coalesce(f.unit_class_names, '{}'::text[])
    from combined g
    -- media type 1 is sheet, 3 is roll
    left join lateral (
        select mpl.material_name,
               (mpl.line_json ->> 'material_media_type_id')::integer as material_media_type_id,
               coalesce(mpl.line_json -> 'specs', '[]'::jsonb)      as specs
        from mapping.material_production_line mpl
        where mpl.material_id        = g.material_id
          and mpl.production_line_id = g.production_line_id
    ) m on true
    left join status   s  on s.material_id  = g.material_id and s.production_line_id  = g.production_line_id and s.delivery_hours  is not distinct from g.delivery_hours
    left join part     pt on pt.material_id = g.material_id and pt.production_line_id = g.production_line_id and pt.delivery_hours is not distinct from g.delivery_hours
    left join flag     f  on f.material_id  = g.material_id and f.production_line_id  = g.production_line_id and f.delivery_hours  is not distinct from g.delivery_hours
    cross join lateral (
        -- computed from the rounded values, so the column adds up with the
        -- sqm and rework_sqm shown next to it; without inflow the forecast
        -- carries the gross sqm, so a forecast-only row still gets a size
        select case when round(g.sqm, 2) + round(g.rework_sqm, 2) > 0
                    then round((round(g.sqm, 2) + round(g.rework_sqm, 2))
                               * (1 + p_waste_percentage / 100), 2)
                    else round(coalesce(g.forecast_sqm, 0)
                               * (1 + p_waste_percentage / 100), 2)
               end as gross_sqm
    ) c
    order by g.material_id, g.production_line_id, g.delivery_hours;
$$;

alter function mapping.get_production_orderline_aggregate(timestamp with time zone, text, integer, integer, boolean, boolean, integer[], text[], integer[], bigint[], integer, integer[], integer[], boolean, numeric, integer, integer) owner to xfw3;
