create function legacy.get_resource_shift_employees(p_model text, p_until timestamp with time zone) returns TABLE(shift_planning_id integer, shift_type text, content jsonb, department_group_id integer, start_at timestamp with time zone, group_name text, employee_id integer, personnel_number text, first_name text, infix text, last_name text, contract_type text)
	stable
	language sql
as $$
WITH matching_resources AS (
    -- Resources that belong to the requested production line model
    SELECT r.resource_uid
    FROM relation.resource r
    JOIN relation.production_line pl ON pl.line_id = r.line_id
    WHERE pl.model = p_model
),
plans AS (
    -- Shift planning for the business date of p_until (Amsterdam time)
    SELECT
        sp.shift_planning_id,
        sp.department_group_id,
        sp.business_date,
        (sp.shift_json->>'start_at')::timestamptz AS start_at,
        sp.shift_json
    FROM log.hr_shift_planning sp
    JOIN matching_resources mr ON mr.resource_uid = sp.shift_json->>'resource_uid'
    WHERE sp.business_date = (p_until AT TIME ZONE 'Europe/Amsterdam')::date
),
shift_lookup AS (
    SELECT item->>'code' AS code, item->'block'->'i18n' AS block
    FROM legacy.lookup lu
    CROSS JOIN LATERAL jsonb_array_elements(lu.lookup_json) AS item
    WHERE lu.lookup = 'lookup_shift'
)
SELECT DISTINCT
    p.shift_planning_id,
    hd.shift                        AS shift_type,
    sl.block                        AS content,
    p.department_group_id,
    p.start_at,
    grp->>'group'                   AS group_name,
    (emp->>'employee_id')::integer  AS employee_id,
    emp->>'personnel_number'        AS personnel_number,
    emp->>'first_name'              AS first_name,
    NULLIF(emp->>'infix', '')       AS infix,
    emp->>'last_name'               AS last_name,
    emp->>'contract_type'           AS contract_type
FROM plans p
CROSS JOIN LATERAL jsonb_array_elements(p.shift_json->'plan'->'groups') AS grp
CROSS JOIN LATERAL jsonb_array_elements(grp->'employees')               AS emp
-- Shift type (day/night) comes from the clock data, per employee per business date
LEFT JOIN LATERAL (
    SELECT h.shift
    FROM log.hr_data h
    WHERE h.employee_id = (emp->>'employee_id')::integer
      AND h.business_date = p.business_date
    ORDER BY h.start_at DESC
    LIMIT 1
) hd ON true
LEFT JOIN shift_lookup sl ON sl.code = hd.shift
ORDER BY p.department_group_id, group_name, last_name, first_name;
$$;

alter function legacy.get_resource_shift_employees(text, timestamp with time zone) owner to xfw3;

