create function get_production_orderline_detail(p_from timestamp with time zone DEFAULT CURRENT_DATE, p_date_type text DEFAULT 'logistics'::text, p_look_back_days integer DEFAULT NULL::integer, p_look_ahead_days integer DEFAULT NULL::integer, p_include_weekend boolean DEFAULT true, p_include_mandatory_dates boolean DEFAULT true, p_status_sequences integer[] DEFAULT NULL::integer[], p_production_line_id integer DEFAULT NULL::integer, p_material_ids integer[] DEFAULT NULL::integer[], p_batch_ids integer[] DEFAULT NULL::integer[], p_nest_ids bigint[] DEFAULT NULL::bigint[], p_is_open boolean DEFAULT true, p_threshold integer DEFAULT 1, p_domain_id integer DEFAULT 1) returns TABLE(number text, order_sequence integer, order_id integer, production_order_id integer, production_orderline_id integer, sales_orderline_id integer, customer_json jsonb, material_id integer, material_name text, product_amount numeric, sqm numeric, ship_separately boolean, production_line_id integer, internal_status_code text, status_sequence integer, status_level text, status_title text, status_json jsonb, part_amount integer, part_status_json jsonb, nest_date date, production_date date, logistics_date date, logistics_at timestamp without time zone, shipment_date date, dates_json jsonb, rework_json jsonb, rejected_amount numeric, produced_amount numeric, nest_json jsonb, nest_ids bigint[], delivery_class_names text[], class_names text[], unit_class_names text[])
	stable
	SET plan_cache_mode=force_custom_plan
	language plpgsql
as $$
    #variable_conflict use_column
declare
    v_zone  constant text     := 'Europe/Amsterdam';
    v_alert constant interval := interval '2 hours';
    v_day   date      := (p_from at time zone 'Europe/Amsterdam')::date;
    v_now   timestamp := (now()  at time zone 'Europe/Amsterdam');
    v_from  date;
    v_until date;
    -- Scope: batch wins over nest, nest wins over the date window.
    v_scope text := case when p_batch_ids is not null then 'batch'
                         when p_nest_ids  is not null then 'nest'
                         else 'window' end;
begin
    -- Window edges counted on action.dates, so look ahead 5 lands on the fifth
    -- day that is in scope, not on the fifth calendar day. p_include_* true
    -- means the column is not filtered on. Everything between the two edges is
    -- returned, so the filter below stays a plain range on one column.
    -- A NULL count means no days on that side; both NULL means no window.
    if v_scope = 'window'
       and (p_look_back_days is not null or p_look_ahead_days is not null) then
        v_from := coalesce((
            select d.date from action.dates d
            where d.date <= v_day
              and (p_include_weekend         or not d.is_weekend)
              and (p_include_mandatory_dates or not d.is_mandatory_day_off)
            order by d.date desc offset coalesce(p_look_back_days, 0) limit 1
        ), v_day);

        v_until := coalesce((
            select d.date from action.dates d
            where d.date >= v_day
              and (p_include_weekend         or not d.is_weekend)
              and (p_include_mandatory_dates or not d.is_mandatory_day_off)
            order by d.date offset coalesce(p_look_ahead_days, 0) limit 1
        ), v_day) + 1;   -- half open
    end if;

    return query
    -- Everything the filters can decide on their own, so all the enrichment
    -- below runs over the rows in scope only, once per set instead of once
    -- per row.
    with orderline_base as (
        select cs.number, cs.order_sequence, cs.order_id, cs.production_order_id,
               cs.production_orderline_id, cs.sales_orderline_id,
               cs.customer_id, cs.company_name, cs.customer_reference, cs.team_name,
               cs.material_id, cs.product_amount, cs.sqm, cs.ship_separately,
               cs.first_production_line_id, cs.internal_status_code,
               cs.nest_date, cs.production_date, cs.logistics_date, cs.shipment_date,
               cs.order_date, cs.production_order_amount,
               ist.sequence as status_sequence, ist.level as status_level,
               ist.internal_title as status_title
        from mapping.component_specs cs
        join mapping.internal_status ist
          on ist.code      = cs.internal_status_code
         and ist.domain_id = p_domain_id
        where cs.domain_id = p_domain_id
          and ist.group_name is distinct from 'Cancelled'
          and (p_is_open is null or cs.is_open = p_is_open)
          and (p_status_sequences is null or ist.sequence = any (p_status_sequences))
          and (p_production_line_id is null or cs.first_production_line_id = p_production_line_id)
          and (p_material_ids is null or cs.material_id = any (p_material_ids))
          -- One branch per date, so the comparison stays on a single column.
          and (v_scope <> 'window' or v_from is null
               or (p_date_type = 'logistics'
                   and cs.logistics_date >= v_from and cs.logistics_date < v_until)
               or (p_date_type = 'production'
                   and cs.production_date >= v_from and cs.production_date < v_until)
               or (p_date_type = 'nest'
                   and cs.nest_date >= (v_from::timestamp  at time zone v_zone)
                   and cs.nest_date <  (v_until::timestamp at time zone v_zone))
               or (p_date_type = 'shipment'
                   and cs.shipment_date >= v_from and cs.shipment_date < v_until))
    ),
    -- The nests of these orderlines, resolved once. Serves three purposes:
    -- the batch and nest scope, nest_json, and the nest rework.
    -- TODO: confirm the cancel marker on legacy.nest and legacy.batch.
    orderline_nest as (
        select ob.production_orderline_id, sp.nest_id, n.batch_id,
               sum(sp.amount) as amount
        from orderline_base ob
        join legacy.single_product sp on sp.production_orderline_id = ob.production_orderline_id
        join legacy.nest n            on n.nest_id  = sp.nest_id
        left join legacy.batch b      on b.batch_id = n.batch_id
        where lower(coalesce(n.nest_json  ->> 'status', '')) not like 'cancel%'
          and lower(coalesce(b.batch_json ->> 'status', '')) not like 'cancel%'
        group by ob.production_orderline_id, sp.nest_id, n.batch_id
    ),
    -- Only one of the three scopes is active, the other two fall away.
    in_scope as (
        select distinct onst.production_orderline_id
        from orderline_nest onst
        where (v_scope = 'batch' and onst.batch_id = any (p_batch_ids))
           or (v_scope = 'nest'  and onst.nest_id  = any (p_nest_ids))
    ),
    -- Rework on a nest means the whole nest was run again: every piece of
    -- this orderline on that nest was produced again, once per rerun.
    nest_agg as (
        select onst.production_orderline_id,
               jsonb_agg(jsonb_build_object('nest_id', onst.nest_id, 'amount', onst.amount)
                         order by onst.nest_id)         as nest_json,
               array_agg(onst.nest_id order by onst.nest_id) as nest_ids,
               coalesce(sum(r.rework_count), 0)::integer      as nest_rework_count,
               coalesce(sum(onst.amount * r.rework_amount), 0) as nest_rework_amount
        from orderline_nest onst
        left join (
            select ir.object_id                          as nest_id,
                   count(*)                              as rework_count,
                   coalesce(sum(ir.object_amount), 0)    as rework_amount
            from mapping.internal_rework ir
            where ir.object_type = 'nest'
              and ir.domain_id   = p_domain_id
              and ir.deleted_at  is null
              and ir.object_id in (select nest_id from orderline_nest)
            group by ir.object_id
        ) r on r.nest_id = onst.nest_id
        group by onst.production_orderline_id
    ),
    -- Rework booked on the orderline itself.
    orderline_rework as (
        select ir.production_orderline_id,
               count(*)::integer                  as rework_count,
               coalesce(sum(ir.object_amount), 0) as rework_amount,
               array_remove(array_agg(ir.order_log_id), null::integer) as order_log_ids
        from mapping.internal_rework ir
        join orderline_base ob on ob.production_orderline_id = ir.production_orderline_id
        where ir.object_type is distinct from 'nest'
          and ir.domain_id  = p_domain_id
          and ir.deleted_at is null
        group by ir.production_orderline_id
    ),
    -- Progress of the orderlines in scope, read once.
    progress as (
        select p.production_orderline_id, p.status_path, p.status_times,
               p.part_statuses, p.part_amount,
               coalesce(array_length(p.part_amount, 1), 0) as part_amount_count,
               array_length(p.part_statuses, 1)            as part_status_count,
               (select sum(x) from unnest(p.part_amount) x) as part_amount_sum
        from mapping.production_orderline_progress p
        join orderline_base ob on ob.production_orderline_id = p.production_orderline_id
        where p.domain_id = p_domain_id
    ),
    -- The path of statuses the orderline went through.
    status_json_agg as (
        select pg.production_orderline_id,
               jsonb_agg(jsonb_build_object(
                   'sequence',             s.sequence,
                   'internal_status_code', si.code,
                   'class_names',          jsonb_build_array(si.class_name),
                   'i18n',                 si.i18n,
                   'duration_in_seconds',  pg.status_times[s.ord]
               ) order by s.ord) as status_json
        from progress pg
        cross join lateral unnest(pg.status_path) with ordinality as s(sequence, ord)
        left join mapping.internal_status si
               on si.sequence = s.sequence and si.domain_id = p_domain_id
        where pg.status_path is not null
        group by pg.production_orderline_id
    ),
    -- The statuses of the product parts.
    part_status_json_agg as (
        select pc.production_orderline_id,
               jsonb_agg(jsonb_build_object(
                   'sequence',             pc.part_status,
                   'internal_status_code', si.code,
                   'class_names',          jsonb_build_array(si.class_name),
                   'i18n',                 si.i18n,
                   'amount',               pc.amount
               ) order by pc.part_status) as part_status_json
        from (
            select pg.production_orderline_id, u.part_status,
                   -- part_amount can be shorter than part_statuses; then the
                   -- total is spread evenly instead.
                   case when pg.part_amount_count < pg.part_status_count
                        then pg.part_amount_sum::numeric / pg.part_status_count
                        else pg.part_amount[u.ord]::numeric
                   end as amount
            from progress pg
            cross join lateral unnest(pg.part_statuses) with ordinality as u(part_status, ord)
            where pg.part_statuses is not null
        ) pc
        left join mapping.internal_status si
               on si.sequence = pc.part_status and si.domain_id = p_domain_id
        group by pc.production_orderline_id
    ),
    -- One name per material, only for the materials in scope.
    material_name as (
        select distinct on (mpl.material_id)
               mpl.material_id,
               mpl.line_json ->> 'material_name' as material_name
        from mapping.material_production_line mpl
        where mpl.material_id in (select material_id from orderline_base)
        order by mpl.material_id
    )
    select
        ob.number,
        ob.order_sequence,
        ob.order_id,
        ob.production_order_id,
        ob.production_orderline_id,
        ob.sales_orderline_id,
        jsonb_build_object(
            'customer_id',        ob.customer_id,
            'company_name',       ob.company_name,
            'customer_reference', ob.customer_reference,
            'team_name',          ob.team_name
        ),
        ob.material_id,
        mn.material_name,
        ob.product_amount,
        ob.sqm,
        coalesce(ob.ship_separately, false),
        ob.first_production_line_id,
        ob.internal_status_code,
        ob.status_sequence,
        ob.status_level,
        ob.status_title,
        coalesce(sja.status_json, '[]'::jsonb),
        coalesce((select sum(x) from unnest(pg.part_amount) x), 0)::integer,
        coalesce(psja.part_status_json, '[]'::jsonb),
        -- nest_date is the only timestamptz of the four dates
        (ob.nest_date at time zone v_zone)::date,
        ob.production_date::date,
        ob.logistics_date::date,
        ob.logistics_date,
        ob.shipment_date::date,
        jsonb_build_object(
            'order_date',    ob.order_date::date,
            'nest_at',       (ob.nest_date at time zone v_zone),
            'production_at', ob.production_date,
            'shipment_at',   ob.shipment_date
        ),
        jsonb_build_object(
            'count',         coalesce(orw.rework_count, 0),
            'amount',        coalesce(orw.rework_amount, 0),
            'sqm',           ob.sqm / nullif(ob.product_amount, 0) * coalesce(orw.rework_amount, 0),
            'nest_count',    coalesce(na.nest_rework_count, 0),
            'nest_amount',   coalesce(na.nest_rework_amount, 0),
            'nest_sqm',      ob.sqm / nullif(ob.product_amount, 0)
                             * coalesce(na.nest_rework_amount, 0),
            'order_log_ids', orw.order_log_ids
        ),
        -- Redone pieces: booked on the orderline plus the reruns of its nests.
        coalesce(orw.rework_amount, 0) + coalesce(na.nest_rework_amount, 0),
        ob.product_amount
            + coalesce(orw.rework_amount, 0) + coalesce(na.nest_rework_amount, 0),
        coalesce(na.nest_json, '[]'::jsonb),
        coalesce(na.nest_ids, '{}'::bigint[]),
        -- Delayed means: logistics day strictly before the viewed day. Kept
        -- apart from class_names, because the board groups its cells on it.
        case when ob.logistics_date::date < v_day then array['state-delayed'] end,
        -- Sorted, because consumers group on this array and array comparison
        -- is order sensitive.
        array(select distinct c from unnest(array[
            case when ob.logistics_date::date < v_day then 'state-delayed' end,
            case when ob.status_sequence < 450 then
                case when (ob.nest_date at time zone v_zone) - v_now <= v_alert
                     then 'plan-alert' else 'plan-signal' end
            end,
            -- rework on the orderline itself or on one of its nests
            case when coalesce(orw.rework_count, 0) > 0
                   or coalesce(na.nest_rework_count, 0) > 0 then 'plan-rework' end
        ]) c where c is not null order by c),
        -- production_order_amount is kept on the row, so no aggregate needed
        case when ob.production_order_amount is null then '{}'::text[]
             when ob.production_order_amount <= p_threshold then array['units-lte-threshold']
             else array['units-gt-threshold'] end
    from orderline_base ob
    left join nest_agg na               on na.production_orderline_id   = ob.production_orderline_id
    left join orderline_rework orw      on orw.production_orderline_id  = ob.production_orderline_id
    left join progress pg               on pg.production_orderline_id   = ob.production_orderline_id
    left join status_json_agg sja       on sja.production_orderline_id  = ob.production_orderline_id
    left join part_status_json_agg psja on psja.production_orderline_id = ob.production_orderline_id
    left join material_name mn          on mn.material_id = ob.material_id
    where v_scope = 'window'
       or ob.production_orderline_id in (select production_orderline_id from in_scope)
    order by ob.production_order_id, ob.production_orderline_id;
end;
$$;

alter function get_production_orderline_detail(timestamp with time zone, text, integer, integer, boolean, boolean, integer[], integer, integer[], integer[], bigint[], boolean, integer, integer) owner to xfw3;

