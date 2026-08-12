create function get_nest_status_by_bucket(p_bucket_name text, p_from date) returns TABLE(bucket_name text, batch_id integer, nest_id integer, nest_name text, waste_percentage numeric, nest_status_json jsonb)
	stable
	language sql
as $$
    WITH plan AS (
        SELECT DISTINCT
            (action_json->>'batch_id')::int AS batch_id
        FROM action.object
        JOIN relation.resource
          ON (object.action_json->>'resource_id')::int = (resource.resource_json->>'pv2_id')::int
        WHERE object.start_at >= p_from
          AND object.start_at <  p_from + INTERVAL '1 day'
          AND (object.action_json->'data'->>'material_id')::int IS NOT NULL
          AND resource.step = 'print'
    ),
    nests AS (
        SELECT
            SUBSTR(nest.nest_json->>'printfile_name', STRPOS(nest.nest_json->>'printfile_name', '_') + 1) AS bucket_name,
            plan.batch_id,
            nest.nest_id,
            nest.nest_name,
            (nest.nest_json->>'waste_percentage')::numeric AS waste_percentage
        FROM legacy.nest
        JOIN plan
          ON nest.nest_json->>'batch_id' = plan.batch_id::text
        WHERE SUBSTR(nest.nest_json->>'printfile_name', STRPOS(nest.nest_json->>'printfile_name', '_') + 1) = p_bucket_name
    ),
    -- One set-based call for all nests, then re-aggregate to one json blob per nest
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
            ARRAY(SELECT nest_id FROM nests)::bigint[]
        ) ns
        GROUP BY ns.nest_id
    )
    SELECT
        n.bucket_name,
        n.batch_id,
        n.nest_id,
        n.nest_name,
        n.waste_percentage,
        s.nest_status_json
    FROM nests n
    LEFT JOIN status s ON s.nest_id = n.nest_id
    ORDER BY n.nest_id;
$$;

alter function get_nest_status_by_bucket(text, date) owner to xfw3;

