create function mapping.calculate_nest_date(p_order_date date, p_production_hours integer, p_tenant_ids integer[] DEFAULT NULL::integer[]) returns timestamp with time zone
	stable
	parallel safe
	language sql
as $$
    -- Nest moment for an order: the working-day rank from the first
    -- working day at or after the order date, with the nest_time of the
    -- production_hours code from lookup_nest_moments.
    --
    -- greatest(hours / 24 - 1, 1): everything up to and including 48
    -- nests on that same working day (rank 1); 72 -> 2, 96 -> 3, 120 -> 4.
    -- Integer division is intentional (30 / 24 = 1).
    --
    -- Returns null when the code is missing from the lookup or the
    -- calendar runs out, so an unresolvable order is visible as null
    -- rather than carrying a fabricated moment.
    SELECT nd.date + (nm.value -> 'nest_time' ->> 'time')::timetz
    FROM (
        SELECT d.date
        FROM action.dates d
        WHERE d.date >= p_order_date
          AND d.is_weekend = false
          AND NOT action.is_day_off(d.tenants_mandatory_day_off, p_tenant_ids)
        ORDER BY d.date
        OFFSET greatest(p_production_hours / 24 - 1, 1) - 1
        LIMIT 1
    ) nd
    JOIN production.lookup l
      ON l.lookup = 'lookup_nest_moments'
    JOIN LATERAL jsonb_array_elements(l.lookup_json) AS c(value)
      ON c.value ->> 'code' = p_production_hours::text
    CROSS JOIN LATERAL jsonb_array_elements(c.value -> 'nest_moments') AS nm(value)
    ORDER BY (nm.value -> 'nest_time' ->> 'time')::timetz
    LIMIT 1;
$$;

alter function mapping.calculate_nest_date(date, integer, integer[]) owner to xfw3;

