create function get_component_specs_with_manifest(p_nest_date date, p_production_line_id integer, p_status_sequence_range integer[] DEFAULT NULL::integer[], p_scope text DEFAULT NULL::text) returns TABLE(nest_date timestamp with time zone, production_orderline_id integer, sales_orderline_id integer, material_id integer, internal_status_code text, scope text, option_codes text[], i18n jsonb)
	language plpgsql
as $$
#variable_conflict use_column
BEGIN
    -- Component specs for one nest date and production line, joined with their
    -- aggregated manifest. p_status_sequence_range [from, to] filters on the
    -- sequence of the current internal status; NULL skips the status filter.
    -- Specs without manifest rows are kept with NULL option_codes so gaps stay visible.
    -- p_scope NULL returns all scopes.
    RETURN QUERY
    WITH specs AS (
        SELECT cs.nest_date,
               cs.production_orderline_id,
               cs.sales_orderline_id,
               cs.material_id,
               cs.internal_status_code
        FROM   mapping.component_specs cs
        JOIN   mapping.internal_status ist
               ON ist.code = cs.internal_status_code
        WHERE  cs.nest_date >= p_nest_date
          AND  cs.nest_date <  p_nest_date + 1
          AND  cs.is_open = true
          AND  cs.first_production_line_id = p_production_line_id
          AND  (p_status_sequence_range IS NULL
                OR ist.sequence BETWEEN p_status_sequence_range[1]
                                    AND p_status_sequence_range[2])
    )
    SELECT s.nest_date,
           s.production_orderline_id,
           s.sales_orderline_id,
           s.material_id,
           s.internal_status_code,
           agg.scope,
           agg.option_codes,
           agg.i18n
    FROM   specs s
    LEFT   JOIN mapping.get_unit_manifest_aggregate(
               (SELECT array_agg(x.production_orderline_id) FROM specs x),
               p_scope
           ) AS agg
           ON agg.production_orderline_id = s.production_orderline_id
    ORDER  BY s.production_orderline_id, agg.scope;
END;
$$;

alter function get_component_specs_with_manifest(date, integer, integer[], text) owner to xfw3;

