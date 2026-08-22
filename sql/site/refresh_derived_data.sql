create function site.refresh_derived_data() returns void
	language plpgsql
as $$
#variable_conflict use_column
begin
    -- state shift aggregation
    perform log.upsert_state_shift_agg(current_date - 1);  -- finalize yesterday
    perform log.upsert_state_shift_agg(current_date);      -- refresh today

    -- materialized views
    refresh materialized view mapping.v_resource_capacity;

    -- the material resource plan: one per workday per line type, created
    -- ahead of time — the plannable items are generated from this planning
    -- later, so the plan must exist before any item does
    insert into action.plan (plan_date, steps, type, line_type)
    select d.date, '{print}', 'material-resource-plan', lt.line_type
    from (select distinct dt.date
          from action.dates dt
          where dt.date >= current_date
            and dt.date < current_date + 14
            and not dt.is_weekend
            and not dt.is_mandatory_day_off) d
    cross join (select distinct pl.line_type
                from relation.production_line pl
                where pl.line_type is not null) lt
    where not exists (select 1 from action.plan p
                      where p.plan_date = d.date
                        and p.type = 'material-resource-plan'
                        and p.line_type = lt.line_type);
end;
$$;

alter function site.refresh_derived_data() owner to xfw3;

