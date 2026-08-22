create function action.get_date_window(p_from timestamp with time zone DEFAULT CURRENT_DATE, p_look_back_days integer DEFAULT NULL::integer, p_look_ahead_days integer DEFAULT NULL::integer, p_include_weekend boolean DEFAULT true, p_include_mandatory_days_off boolean DEFAULT true, p_tenant_ids integer[] DEFAULT NULL::integer[]) returns TABLE(from_date date, until_date date)
	stable
	language sql
as $$
    -- Window edges counted on action.dates, so look ahead 5 lands on the fifth
    -- day that is in scope, not on the fifth calendar day. p_include_* true
    -- means the column is not filtered on. until_date is half open. Both
    -- counts NULL means no window: no row.
    with day as (
        select (p_from at time zone 'Europe/Amsterdam')::date as day
    )
    select
        coalesce((select d.date from action.dates d
                  where d.date <= day.day
                    and (p_include_weekend            or not d.is_weekend)
                    and (p_include_mandatory_days_off or not (coalesce(p_tenant_ids, d.tenants_mandatory_day_off) <@ d.tenants_mandatory_day_off and d.tenants_mandatory_day_off <> '{}'))
                  order by d.date desc offset coalesce(p_look_back_days, 0) limit 1), day.day),
        coalesce((select d.date from action.dates d
                  where d.date >= day.day
                    and (p_include_weekend            or not d.is_weekend)
                    and (p_include_mandatory_days_off or not (coalesce(p_tenant_ids, d.tenants_mandatory_day_off) <@ d.tenants_mandatory_day_off and d.tenants_mandatory_day_off <> '{}'))
                  order by d.date offset coalesce(p_look_ahead_days, 0) limit 1), day.day) + 1
    from day
    where p_look_back_days is not null or p_look_ahead_days is not null;
$$;

alter function action.get_date_window(timestamp with time zone, integer, integer, boolean, boolean, integer[]) owner to xfw3;
