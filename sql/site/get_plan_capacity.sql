create function get_plan_capacity() returns TABLE(week integer, day_name text, day integer, month_name text, year integer, info text, resources jsonb)
	language sql
as $$
    SELECT
        26          AS week,
        'Monday'    AS day_name,
        13          AS day,
        'January'   AS month_name,
        2025        AS year,
        NULL::text  AS info,
        jsonb_build_array(
            jsonb_build_object(
                'id',        1,
                'title',     'Team A',
                'team',      'Production',
                'timeslots', jsonb_build_array(
                    jsonb_build_object(
                        'id',       1,
                        'duration', 480,
                        'tasks',    jsonb_build_array(
                            jsonb_build_object(
                                'id',               101,
                                'title',            'Job #1001',
                                'duration_minutes', 90,
                                'state',            'in_progress',
                                'colors',           jsonb_build_object(
                                    'planned', jsonb_build_object('background', '#3b82f6', 'color', '#ffffff')
                                )
                            ),
                            jsonb_build_object(
                                'id',               102,
                                'title',            'Job #1002',
                                'duration_minutes', 120,
                                'state',            'pending',
                                'colors',           jsonb_build_object(
                                    'planned', jsonb_build_object('background', '#10b981', 'color', '#ffffff')
                                )
                            )
                        )
                    )
                )
            ),
            jsonb_build_object(
                'id',        2,
                'title',     'Team B',
                'team',      'Production',
                'timeslots', jsonb_build_array(
                    jsonb_build_object(
                        'id',       2,
                        'duration', 480,
                        'tasks',    jsonb_build_array(
                            jsonb_build_object(
                                'id',               201,
                                'title',            'Job #2001',
                                'duration_minutes', 60,
                                'state',            'done',
                                'colors',           jsonb_build_object(
                                    'planned', jsonb_build_object('background', '#f59e0b', 'color', '#ffffff')
                                )
                            )
                        )
                    )
                )
            )
        ) AS resources;
$$;

alter function get_plan_capacity() owner to xfw3;

