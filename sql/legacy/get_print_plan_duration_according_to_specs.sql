create function legacy.get_print_plan_duration_according_to_specs(p_action_id integer) returns numeric
	language plpgsql
as $$
DECLARE
    printoverlap_level integer := 3;
    print_passes integer := 2;
    horizontal_resolution integer := 900;
    vertical_resolution integer := 1200;
    print_duration numeric(20,2);
BEGIN
    WITH object_cte AS (
        SELECT
            data.nodes,
            data.connections,
            eq.print_speed_sqm,
            eq.media_width,
            actionjson.width,
            actionjson.height,
            CASE
                WHEN actionjson.name ILIKE '%-dz%' OR actionjson.name ILIKE '%-ds%' THEN 2 * actionjson.amount
                ELSE actionjson.amount
            END AS amount
        FROM action.object o
        CROSS JOIN LATERAL jsonb_to_record(o.action_json) AS actionjson(
            print_width numeric(10,2),
            print_height numeric(10,2),
            width numeric(10,2),
            height numeric(10,2),
            amount integer,
            name text,
            pv2resource_id integer
        )
        JOIN relation.resource r
            ON actionjson.pv2resource_id = (r.resource_json #>> '{pv2resourceId}')::integer
        JOIN relation.equipment e
            ON (r.resource_json #>> '{equipmentId}')::integer = e.equipment_id
        CROSS JOIN LATERAL jsonb_to_record(e.equipment_json -> 'data') AS data(
            nodes jsonb,
            connections jsonb,
            modi jsonb
        )
        CROSS JOIN LATERAL jsonb_to_recordset(data.modi) AS eq(
            print_passes integer,
            horizontal_resolution integer,
            vertical_resolution integer,
            passoverlap_level integer,
            print_speed_sqm integer,
            media_width integer
        )
        WHERE o.action_id = p_action_id
          AND eq.print_passes = print_passes
          AND eq.passoverlap_level = printoverlap_level
          AND eq.horizontal_resolution = horizontal_resolution
          AND eq.vertical_resolution = vertical_resolution
    )
    SELECT
        public.evaluate_formula(
            (SELECT jsonb_build_object('nodes', nodes, 'connections', connections) FROM object_cte LIMIT 1),
            (SELECT jsonb_build_object(
                        'printSpeedSqm', print_speed_sqm,
                        'mediaWidth', media_width,
                        'width', CASE WHEN height > width AND height <= media_width THEN GREATEST(width, height) ELSE width END,
                        'height', CASE WHEN height > width AND height <= media_width THEN LEAST(width, height) ELSE height END
                    ) FROM object_cte LIMIT 1)
        ) * COALESCE(amount, 1)::numeric(10,2)
    INTO print_duration
    FROM object_cte
    LIMIT 1;

    RETURN print_duration;
END;
$$;

alter function legacy.get_print_plan_duration_according_to_specs(integer) owner to xfw3;

