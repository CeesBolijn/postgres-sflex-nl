create function get_batch_orderlines(p_batch_id integer, p_from timestamp with time zone) returns TABLE(nest_id integer, nest_name text, waste_percentage numeric, nest_amount numeric, nest_status_json jsonb, start_at timestamp with time zone, duration_seconds integer, production_date timestamp without time zone, production_orderline_id integer, product_amount numeric, product_width numeric, product_height numeric, customer_id integer, company_name text, class_names text[])
	stable
	language sql
as $$
    WITH batch_timing AS (
        SELECT
            min(object.start_at) AS start_at,
            FLOOR(EXTRACT(EPOCH FROM sum(object.end_at - object.start_at)))::integer AS duration_seconds
        FROM action.object
        JOIN relation.resource
          ON (object.action_json->>'resource_id')::int = (resource.resource_json->>'pv2_id')::int
        WHERE (object.action_json->>'batch_id')::int = p_batch_id
          AND resource.step = 'print'
    ),
    alert_from AS (
        SELECT interval_date
        FROM action.get_interval_dates(
            p_reference_date  => p_from::date,
            p_current_date    => p_from::date,
            p_interval        => 1,
            p_look_ahead_days => 1,
            p_day_offset      => 2
        )
    ),
    -- Nests in this batch, resolved once
    batch_nests AS (
        SELECT DISTINCT nest.nest_id, nest.nest_name,
               (nest.nest_json->>'waste_percentage')::numeric AS waste_percentage,
               nest.amount AS nest_amount
        FROM legacy.nest
        WHERE nest.batch_id = p_batch_id
    ),
    -- One set-based status call for every nest in the batch
    status AS (
        SELECT
            ns.nest_id,
            jsonb_agg(
                jsonb_build_object(
                    'code',               ns.code,
                    'sequence',           ns.status_sequence,
                    'current_amount',     ns.current_amount,
                    'last_moved_at',      ns.last_moved_at,
                    'last_resource_uids', ns.last_resource_uids
                ) ORDER BY ns.status_sequence
            ) AS nest_status_json
        FROM legacy.get_nest_status(
            ARRAY(SELECT nest_id FROM batch_nests)::bigint[]
        ) ns
        GROUP BY ns.nest_id
    )
    SELECT DISTINCT
        bn.nest_id,
        bn.nest_name,
        bn.waste_percentage,
        bn.nest_amount,
        st.nest_status_json,
        bt.start_at,
        bt.duration_seconds,
        cs.production_date,
        cs.production_orderline_id,
        cs.product_amount,
        cs.product_width,
        cs.product_height,
        cs.customer_id,
        cs.company_name,
        CASE
            WHEN cs.production_date::date > alert_from.interval_date THEN ARRAY['plan-warning']
            ELSE NULL
        END AS class_names
    FROM batch_nests bn
    JOIN legacy.single_product sp
      ON sp.nest_id = bn.nest_id
    JOIN mapping.component_specs cs
      ON cs.production_orderline_id = sp.production_orderline_id
    LEFT JOIN status st ON st.nest_id = bn.nest_id
    CROSS JOIN batch_timing bt
    CROSS JOIN alert_from
    ORDER BY cs.production_date, bn.nest_id, cs.production_orderline_id;
$$;

alter function get_batch_orderlines(integer, timestamp with time zone) owner to xfw3;

