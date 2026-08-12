create function get_nest_bucket_resources(p_nest_bucket_id integer) returns TABLE(resource_uid text, resource_name text, step text)
	stable
	language sql
as $$
    SELECT e.elem ->> 'resource_uid'  AS resource_uid,
           r.resource_json ->> 'name' AS resource_name,
           r.resource_json ->> 'step' AS step
    FROM   mock.nest_bucket nb
    CROSS  JOIN LATERAL jsonb_array_elements(nb.resource_json::jsonb) AS e(elem)
    JOIN   relation.resource r
           ON r.resource_uid = e.elem ->> 'resource_uid'
    WHERE  nb.nest_bucket_id = p_nest_bucket_id
    ORDER  BY (e.elem ->> 'status_sequence')::int, r.resource_json ->> 'name';
$$;

alter function get_nest_bucket_resources(integer) owner to xfw3;

