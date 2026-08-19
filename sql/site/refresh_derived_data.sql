create function refresh_derived_data() returns void
	language plpgsql
as $$
#variable_conflict use_column
begin
    -- state shift aggregation
    perform log.upsert_state_shift_agg(current_date - 1);  -- finalize yesterday
    perform log.upsert_state_shift_agg(current_date);      -- refresh today

    -- materialized views
    refresh materialized view mapping.v_resource_capacity;
end;
$$;

alter function refresh_derived_data() owner to xfw3;

