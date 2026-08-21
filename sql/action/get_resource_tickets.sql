create function action.get_resource_tickets(p_resource_uids text[] DEFAULT NULL::text[]) returns TABLE(action_id integer, content jsonb, start_at timestamp with time zone)
	stable
	language sql
as $$
    SELECT
        o.action_id,
        (o.action_json->>'content')::jsonb,
        o.start_at
    FROM action.object o
    WHERE EXISTS (
        SELECT 1
        FROM jsonb_array_elements_text(o.action_json->'resource_uids') AS r(uid)
        WHERE r.uid = ANY(p_resource_uids)
    )
    ORDER BY o.start_at DESC;
$$;

alter function action.get_resource_tickets(text[]) owner to xfw3;

