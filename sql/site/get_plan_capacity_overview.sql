create function get_plan_capacity_overview() returns TABLE(week integer, day_name text, day integer, month_name text, year integer, info text, resources jsonb)
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
                'pool_size', 2,
                'timeslots', jsonb_build_array(
                    jsonb_build_object(
                        'id',    1,
                        'tasks', jsonb_build_array(
                            jsonb_build_object(
                                'id',       101,
                                'next_id',  102,
                                'title',    'Job #1001',
                                'planned',  jsonb_build_object('start', 60,  'duration', 90,  'duration_before', 0, 'duration_after', 15),
                                'actual',   jsonb_build_object('start', 65,  'duration', 85,  'duration_before', 0, 'duration_after', 10),
                                'colors',   jsonb_build_object(
                                    'planned', jsonb_build_object('background', '#3b82f6', 'color', '#ffffff'),
                                    'actual',  jsonb_build_object('background', '#1d4ed8', 'color', '#ffffff')
                                )
                            ),
                            jsonb_build_object(
                                'id',      102,
                                'title',   'Job #1002',
                                'planned', jsonb_build_object('start', 180, 'duration', 120, 'duration_before', 0, 'duration_after', 0),
                                'actual',  jsonb_build_object('start', 195, 'duration', 110, 'duration_before', 0, 'duration_after', 0),
                                'colors',  jsonb_build_object(
                                    'planned', jsonb_build_object('background', '#10b981', 'color', '#ffffff'),
                                    'actual',  jsonb_build_object('background', '#059669', 'color', '#ffffff')
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
                'pool_size', 1,
                'timeslots', jsonb_build_array(
                    jsonb_build_object(
                        'id',    2,
                        'tasks', jsonb_build_array(
                            jsonb_build_object(
                                'id',      201,
                                'title',   'Job #2001',
                                'planned', jsonb_build_object('start', 30, 'duration', 60, 'duration_before', 0, 'duration_after', 0),
                                'actual',  jsonb_build_object('start', 40, 'duration', 55, 'duration_before', 0, 'duration_after', 0),
                                'colors',  jsonb_build_object(
                                    'planned', jsonb_build_object('background', '#f59e0b', 'color', '#ffffff'),
                                    'actual',  jsonb_build_object('background', '#d97706', 'color', '#ffffff')
                                )
                            )
                        )
                    )
                )
            )
        ) AS resources;
$$;

alter function get_plan_capacity_overview() owner to xfw3;

