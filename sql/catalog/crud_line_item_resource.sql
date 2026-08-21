create function catalog.crud_line_item_resource(p_param_json jsonb, p_no_results boolean DEFAULT false) returns jsonb
	language plpgsql
as $$
-- ============================================================
-- Append-only ledger of allowed resource_uids per line_item.
-- Invariant: the set only shrinks; the latest row is the truth.
-- Payload: array of { crud, line_item_id, ... }, processed in order:
--   narrow : intersect payload resource_uids with the latest set
--            (first narrow seeds the set)
--   commit : planner picks one resource_uid; same-step siblings
--            (relation.resource.step) are dropped, the rest is kept
--   revert : undo a commit — copy the latest non-commit row
--   force  : write the set verbatim (breaks monotonicity), with reason
-- See line_item_resource.md for full semantics.
-- ============================================================
DECLARE
    el       jsonb;
    v_last   text[];
    v_new    text[];
    result   jsonb;
BEGIN
    FOR el IN SELECT * FROM jsonb_array_elements(p_param_json)
    LOOP
        -- latest set for this line_item
        SELECT resource_uids INTO v_last
        FROM core.line_item_resource
        WHERE line_item_id = (el ->> 'line_item_id')::bigint
        ORDER BY line_item_resource_id DESC
        LIMIT 1;

        CASE el ->> 'crud'

        WHEN 'narrow' THEN
            -- intersect with the latest set; first narrow seeds the set
            SELECT array_agg(uid ORDER BY uid) INTO v_new
            FROM jsonb_array_elements_text(el -> 'resource_uids') AS uid
            WHERE v_last IS NULL OR uid = ANY (v_last);

        WHEN 'commit' THEN
            -- keep the chosen resource, drop same-step siblings
            SELECT array_agg(u.uid ORDER BY u.uid) INTO v_new
            FROM unnest(v_last) AS u(uid)
            JOIN relation.resource r ON r.resource_uid = u.uid
            WHERE u.uid = el ->> 'resource_uid'
               OR r.step IS DISTINCT FROM (
                      SELECT step
                      FROM relation.resource
                      WHERE resource_uid = el ->> 'resource_uid');

        WHEN 'revert' THEN
            -- fall back to the latest non-commit row
            SELECT resource_uids INTO v_new
            FROM core.line_item_resource
            WHERE line_item_id = (el ->> 'line_item_id')::bigint
              AND kind <> 'commit'
            ORDER BY line_item_resource_id DESC
            LIMIT 1;

        WHEN 'force' THEN
            SELECT array_agg(uid ORDER BY uid) INTO v_new
            FROM jsonb_array_elements_text(el -> 'resource_uids') AS uid;

        END CASE;

        INSERT INTO core.line_item_resource (line_item_id, kind, resource_uids, reason)
        VALUES ((el ->> 'line_item_id')::bigint, el ->> 'crud', v_new, el ->> 'reason');
    END LOOP;

    IF p_no_results THEN
        RETURN '[]'::jsonb;
    END IF;

    SELECT jsonb_agg(jsonb_build_object(
        'line_item_id',  cur.line_item_id,
        'kind',          cur.kind,
        'resource_uids', to_jsonb(cur.resource_uids),
        'updated_at',    cur.updated_at
    ))
    INTO result
    FROM (
        SELECT DISTINCT ON (line_item_id)
               line_item_id, kind, resource_uids, updated_at
        FROM core.line_item_resource
        WHERE line_item_id IN (
            SELECT DISTINCT (e ->> 'line_item_id')::bigint
            FROM jsonb_array_elements(p_param_json) e)
        ORDER BY line_item_id, line_item_resource_id DESC
    ) cur;

    RETURN COALESCE(result, '[]'::jsonb);
END;
$$;

alter function catalog.crud_line_item_resource(jsonb, boolean) owner to xfw3;

