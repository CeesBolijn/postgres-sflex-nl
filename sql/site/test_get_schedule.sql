create function site.test_get_schedule() returns TABLE(date text, unavailable_resource_ids integer[], info text, timeslots jsonb, resources jsonb)
	language sql
as $$
SELECT *
FROM (VALUES

    -- Unplanned bucket
    (
        NULL::text,
        ARRAY[]::int[],
        NULL::text,
        '[]'::json,
        '[
            {
                "id": 1, "title": "Team Alpha", "total_minutes": 0,
                "visible_when_empty": true, "timeslot_ids": [],
                "tasks": [
                    { "id": 101, "title": "Hang banner at Central Station", "step": "Installation",
                      "state": "unplanned", "duration_minutes": 90, "time_to_start": 15, "time_to_end": 10,
                      "timeslot_id": 0, "resource_id": 1, "sort_order": 0, "draggable": true },
                    { "id": 102, "title": "Replace LED strip Westmall", "step": "Repair",
                      "state": "unplanned", "duration_minutes": 60, "time_to_start": 20, "time_to_end": 10,
                      "timeslot_id": 0, "resource_id": 1, "sort_order": 1, "draggable": true }
                ]
            }
        ]'::json
    ),

    -- Monday
    (
        '2026-06-08',
        ARRAY[3]::int[],
        NULL::text,
        '[
            { "id": 1, "title": "Morning",   "from": "07:00", "till": "12:00" },
            { "id": 2, "title": "Afternoon", "from": "12:00", "till": "17:00" }
        ]'::json,
        '[
            {
                "id": 1, "title": "Team Alpha", "total_minutes": 480,
                "visible_when_empty": true, "timeslot_ids": [1, 2],
                "tasks": [
                    { "id": 201, "title": "Install signage Schiphol Gate B", "step": "Installation",
                      "state": "planned", "duration_minutes": 120, "time_to_start": 30, "time_to_end": 15,
                      "timeslot_id": 1, "resource_id": 1, "sort_order": 0, "draggable": true },
                    { "id": 202, "title": "Calibrate display unit Terminal 2", "step": "Calibration",
                      "state": "planned", "duration_minutes": 90, "time_to_start": 10, "time_to_end": 10,
                      "timeslot_id": 2, "resource_id": 1, "sort_order": 0, "draggable": true }
                ]
            },
            {
                "id": 2, "title": "Team Beta", "total_minutes": 480,
                "visible_when_empty": true, "timeslot_ids": [1],
                "tasks": [
                    { "id": 203, "title": "Remove old frames Centraal", "step": "Removal",
                      "state": "planned", "duration_minutes": 180, "time_to_start": 25, "time_to_end": 20,
                      "timeslot_id": 1, "resource_id": 2, "sort_order": 0, "draggable": true }
                ]
            }
        ]'::json
    ),

    -- Tuesday
    (
        '2026-06-09',
        ARRAY[]::int[],
        NULL::text,
        '[
            { "id": 3, "title": "Morning",   "from": "07:00", "till": "12:00" },
            { "id": 4, "title": "Afternoon", "from": "12:00", "till": "17:00" }
        ]'::json,
        '[
            {
                "id": 1, "title": "Team Alpha", "total_minutes": 480,
                "visible_when_empty": true, "timeslot_ids": [3, 4],
                "tasks": [
                    { "id": 301, "title": "Mount totem Zuidas", "step": "Installation",
                      "state": "planned", "duration_minutes": 150, "time_to_start": 20, "time_to_end": 15,
                      "timeslot_id": 3, "resource_id": 1, "sort_order": 0, "draggable": true }
                ]
            },
            {
                "id": 2, "title": "Team Beta", "total_minutes": 480,
                "visible_when_empty": false, "timeslot_ids": [4],
                "tasks": [
                    { "id": 302, "title": "Repair lightbox Kalverstraat", "step": "Repair",
                      "state": "urgent", "duration_minutes": 60, "time_to_start": 15, "time_to_end": 10,
                      "timeslot_id": 4, "resource_id": 2, "sort_order": 0, "draggable": true },
                    { "id": 303, "title": "Install wrap ARTIS entrance", "step": "Installation",
                      "state": "planned", "duration_minutes": 120, "time_to_start": 10, "time_to_end": 15,
                      "timeslot_id": 4, "resource_id": 2, "sort_order": 1, "draggable": true }
                ]
            }
        ]'::json
    )

) AS t (date, unavailable_resource_ids, info, timeslots, resources);

$$;

alter function site.test_get_schedule() owner to xfw3;

