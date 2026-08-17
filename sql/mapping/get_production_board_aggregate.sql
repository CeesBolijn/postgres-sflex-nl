create or replace function mapping.get_production_board_aggregate(p_from timestamp with time zone DEFAULT CURRENT_DATE, p_look_back_days integer DEFAULT 10, p_look_ahead_days integer DEFAULT 5, p_production_line_id integer DEFAULT NULL::integer, p_domain_id integer DEFAULT 1, p_status_levels text[] DEFAULT NULL::text[]) returns TABLE(status_sequence integer, internal_status_code text, status_title text, logistics_date date, logistics_datetime timestamp without time zone, is_logistics_date_today boolean, delivery_class_names text[], order_count bigint, regular_amount numeric, regular_sqm numeric, rework_count numeric, rework_amount numeric, rework_sqm numeric, day_distribution_json jsonb, distribution_json jsonb, material_id integer, material_name text, material_order_count bigint, material_product_amount numeric, material_sqm numeric, material_rework_count numeric, material_rework_amount numeric, material_rework_sqm numeric, material_distribution_json jsonb, nest_ids bigint[])
	stable
	language plpgsql
as $$
#variable_conflict use_column
declare
    v_day date := (p_from at time zone 'Europe/Amsterdam')::date;
begin
    return query
    with detail as (
        select d.*,
               -- Full timestamp when the logistics moment falls on the viewed
               -- day, otherwise date-only, so only today gets sub-cells.
               case when d.logistics_date = v_day then d.logistics_at
                    else date_trunc('day', d.logistics_at)
               end as logistics_datetime,
               d.logistics_date = v_day as is_logistics_date_today
        from mapping.get_production_orderline_detail(
                 p_from               => p_from,
                 p_date_type          => 'logistics',
                 p_look_back_days     => p_look_back_days,
                 p_look_ahead_days    => p_look_ahead_days,
                 p_production_line_id => p_production_line_id,
                 -- filtered at the scan, not on the rows coming back
                 p_status_levels      => p_status_levels,
                 p_is_open            => true,
                 p_domain_id          => p_domain_id) d
    ),
    -- One row per (cell, material). Every other level in this function is
    -- derived from this grain, so cell totals always equal the sum of their
    -- material rows by construction.
    material as (
        select d.status_sequence, d.internal_status_code, d.status_title,
               d.logistics_date, d.delivery_class_names, d.logistics_datetime,
               d.is_logistics_date_today, d.material_id, d.material_name,
               count(distinct d.production_order_id) as material_order_count,
               sum(d.product_amount)                 as material_product_amount,
               sum(d.sqm)                            as material_sqm,
               sum((d.impact_json ->> 'rework_count')::integer)::numeric
                                                     as material_rework_count,
               sum(d.rejected_amount)                as material_rework_amount,
               sum(d.sqm / nullif(d.product_amount, 0) * d.rejected_amount)
                                                     as material_rework_sqm
        from detail d
        group by d.status_sequence, d.internal_status_code, d.status_title,
                 d.logistics_date, d.delivery_class_names, d.logistics_datetime,
                 d.is_logistics_date_today, d.material_id, d.material_name
    ),
    -- Part-status steps unnested once, at (cell, material, step) grain. Day,
    -- cell and material distributions are all rolled up from these rows.
    step as (
        select d.internal_status_code, d.logistics_date, d.delivery_class_names,
               d.logistics_datetime, d.is_logistics_date_today, d.material_id,
               (p.value ->> 'sequence')::integer    as step_sequence,
               p.value ->> 'internal_status_code'   as step_code,
               p.value ->  'class_names'            as step_class_names,
               p.value ->  'i18n'                   as step_i18n,
               sum((p.value ->> 'amount')::numeric) as step_amount
        from detail d
        cross join lateral jsonb_array_elements(d.part_status_json) as p(value)
        group by d.internal_status_code, d.logistics_date, d.delivery_class_names,
                 d.logistics_datetime, d.is_logistics_date_today, d.material_id,
                 7, 8, 9, 10
    ),
    material_distribution as (
        select s.internal_status_code, s.logistics_date, s.delivery_class_names,
               s.logistics_datetime, s.is_logistics_date_today, s.material_id,
               jsonb_agg(jsonb_build_object(
                   'sequence',             s.step_sequence,
                   'internal_status_code', s.step_code,
                   'class_names',          s.step_class_names,
                   'i18n',                 s.step_i18n,
                   'amount',               s.step_amount) order by s.step_sequence)
                   as material_distribution_json
        from step s
        group by s.internal_status_code, s.logistics_date, s.delivery_class_names,
                 s.logistics_datetime, s.is_logistics_date_today, s.material_id
    ),
    -- Cell distribution: same step rows summed across materials.
    cell_step as (
        select s.internal_status_code, s.logistics_date, s.delivery_class_names,
               s.logistics_datetime, s.is_logistics_date_today,
               s.step_sequence, s.step_code, s.step_class_names, s.step_i18n,
               sum(s.step_amount) as step_amount
        from step s
        group by s.internal_status_code, s.logistics_date, s.delivery_class_names,
                 s.logistics_datetime, s.is_logistics_date_today,
                 s.step_sequence, s.step_code, s.step_class_names, s.step_i18n
    ),
    cell_distribution as (
        select cs.internal_status_code, cs.logistics_date, cs.delivery_class_names,
               cs.logistics_datetime, cs.is_logistics_date_today,
               jsonb_agg(jsonb_build_object(
                   'sequence',             cs.step_sequence,
                   'internal_status_code', cs.step_code,
                   'class_names',          cs.step_class_names,
                   'i18n',                 cs.step_i18n,
                   'amount',               cs.step_amount) order by cs.step_sequence)
                   as distribution_json
        from cell_step cs
        group by cs.internal_status_code, cs.logistics_date, cs.delivery_class_names,
                 cs.logistics_datetime, cs.is_logistics_date_today
    ),
    -- Day distribution: cell steps summed once more across all sub-cells of
    -- the same (status, day). Repeated on every row of that day.
    day_step as (
        select cs.internal_status_code, cs.logistics_date,
               cs.step_sequence, cs.step_code, cs.step_class_names, cs.step_i18n,
               sum(cs.step_amount) as step_amount
        from cell_step cs
        group by cs.internal_status_code, cs.logistics_date,
                 cs.step_sequence, cs.step_code, cs.step_class_names, cs.step_i18n
    ),
    day_distribution as (
        select ds.internal_status_code, ds.logistics_date,
               jsonb_agg(jsonb_build_object(
                   'sequence',             ds.step_sequence,
                   'internal_status_code', ds.step_code,
                   'class_names',          ds.step_class_names,
                   'i18n',                 ds.step_i18n,
                   'amount',               ds.step_amount) order by ds.step_sequence)
                   as day_distribution_json
        from day_step ds
        group by ds.internal_status_code, ds.logistics_date
    ),
    -- Distinct nests per (cell, material).
    material_nest as (
        select d.internal_status_code, d.logistics_date, d.delivery_class_names,
               d.logistics_datetime, d.is_logistics_date_today, d.material_id,
               array_agg(distinct ne.nest_id order by ne.nest_id) as material_nest_ids
        from detail d
        cross join lateral unnest(d.nest_ids) as ne(nest_id)
        group by d.internal_status_code, d.logistics_date, d.delivery_class_names,
                 d.logistics_datetime, d.is_logistics_date_today, d.material_id
    )
    select
        m.status_sequence,
        m.internal_status_code,
        m.status_title,
        m.logistics_date,
        m.logistics_datetime,
        m.is_logistics_date_today,
        m.delivery_class_names,
        -- Cell totals as window sums over the material rows of the same cell:
        -- consistent with the material breakdown by construction.
        (sum(m.material_order_count)   over w)::bigint as order_count,
        sum(m.material_product_amount) over w          as regular_amount,
        sum(m.material_sqm)            over w          as regular_sqm,
        sum(m.material_rework_count)   over w          as rework_count,
        sum(m.material_rework_amount)  over w          as rework_amount,
        sum(m.material_rework_sqm)     over w          as rework_sqm,
        coalesce(dd.day_distribution_json, '[]'::jsonb),
        coalesce(cd.distribution_json, '[]'::jsonb),
        m.material_id,
        m.material_name,
        m.material_order_count,
        m.material_product_amount,
        m.material_sqm,
        m.material_rework_count,
        m.material_rework_amount,
        m.material_rework_sqm,
        coalesce(md.material_distribution_json, '[]'::jsonb),
        coalesce(mn.material_nest_ids, '{}')
    from material m
    left join day_distribution dd
        on dd.internal_status_code = m.internal_status_code
       and dd.logistics_date       = m.logistics_date
    left join cell_distribution cd
        on cd.internal_status_code     = m.internal_status_code
       and cd.logistics_date           = m.logistics_date
       and cd.delivery_class_names     is not distinct from m.delivery_class_names
       and cd.logistics_datetime       is not distinct from m.logistics_datetime
       and cd.is_logistics_date_today  is not distinct from m.is_logistics_date_today
    left join material_distribution md
        on md.internal_status_code     = m.internal_status_code
       and md.logistics_date           = m.logistics_date
       and md.delivery_class_names     is not distinct from m.delivery_class_names
       and md.logistics_datetime       is not distinct from m.logistics_datetime
       and md.is_logistics_date_today  is not distinct from m.is_logistics_date_today
       and md.material_id              is not distinct from m.material_id
    left join material_nest mn
        on mn.internal_status_code     = m.internal_status_code
       and mn.logistics_date           = m.logistics_date
       and mn.delivery_class_names     is not distinct from m.delivery_class_names
       and mn.logistics_datetime       is not distinct from m.logistics_datetime
       and mn.is_logistics_date_today  is not distinct from m.is_logistics_date_today
       and mn.material_id              is not distinct from m.material_id
    window w as (partition by
        m.internal_status_code, m.logistics_date, m.delivery_class_names,
        m.logistics_datetime, m.is_logistics_date_today)
    order by m.status_sequence, m.logistics_date, m.logistics_datetime,
             m.delivery_class_names, m.material_name, m.material_sqm desc;
end;
$$;

alter function mapping.get_production_board_aggregate(timestamp with time zone, integer, integer, integer, integer, text[]) owner to xfw3;

