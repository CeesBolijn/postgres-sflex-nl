create function get_internal_status_codes() returns TABLE(internal_status_id integer, sequence integer, code text, class_name text, i18n jsonb)
	stable
	language sql
as $$
    SELECT DISTINCT ON (s.sequence)
        s.internal_status_id,
        s.sequence,
        s.code,
        s.class_name,
        s.i18n
    FROM mapping.internal_status s
    ORDER BY s.sequence, s.internal_status_id;
$$;

alter function get_internal_status_codes() owner to xfw3;

