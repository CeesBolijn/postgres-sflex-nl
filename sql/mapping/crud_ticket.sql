create function crud_ticket(p_param_json jsonb, p_no_results boolean DEFAULT false) returns TABLE(param_id integer, track_by integer, crud text, domain_id integer, ticket_id integer)
	language plpgsql
as $$
#variable_conflict use_column
DECLARE
    last_updated timestamp;
BEGIN
    INSERT INTO mapping.ticket (
        domain_id, ticket_id, order_id, order_number, customer_id,
        production_line_id, production_order_id,
        type_code, type_name, status, priority,
        credit_status, credit_amount, title, action_item,
        objects_json, created_at, closed_at, solved_at, deleted_at, updated_at
    )
    SELECT
        (el->>'domain_id')::integer,
        (el->>'ticket_id')::integer,
        (el->>'order_id')::integer,
        (el->>'order_number')::integer,
        (el->>'customer_id')::integer,
        (el->>'production_line_id')::integer,
        (el->>'production_order_id')::integer,
        el->>'type_code',
        el->>'type_name',
        el->>'status',
        el->>'priority',
        el->>'credit_status',
        (el->>'credit_amount')::numeric(8,2),
        el->>'title',
        el->>'action_item',
        COALESCE(
            CASE WHEN el->'objects_json' IS NOT NULL AND el->>'objects_json' <> 'null'
                 THEN el->'objects_json'
                 ELSE '[]'::jsonb
            END,
            '[]'::jsonb
        ),
        (el->>'created_at')::timestamptz,
        (el->>'closed_at')::timestamptz,
        (el->>'solved_at')::timestamptz,
        (el->>'deleted_at')::timestamptz,
        (el->>'updated_at')::timestamp
    FROM jsonb_array_elements(p_param_json) AS el
    WHERE el->>'crud' = 'merge'
    ON CONFLICT (ticket_id) DO UPDATE SET
        domain_id           = EXCLUDED.domain_id,
        order_id            = EXCLUDED.order_id,
        order_number        = EXCLUDED.order_number,
        customer_id         = EXCLUDED.customer_id,
        production_line_id  = EXCLUDED.production_line_id,
        production_order_id = EXCLUDED.production_order_id,
        type_code           = EXCLUDED.type_code,
        type_name           = EXCLUDED.type_name,
        status              = EXCLUDED.status,
        priority            = EXCLUDED.priority,
        credit_status       = EXCLUDED.credit_status,
        credit_amount       = EXCLUDED.credit_amount,
        title               = EXCLUDED.title,
        action_item         = EXCLUDED.action_item,
        objects_json        = EXCLUDED.objects_json,
        created_at          = EXCLUDED.created_at,
        closed_at           = EXCLUDED.closed_at,
        solved_at           = EXCLUDED.solved_at,
        deleted_at          = EXCLUDED.deleted_at,
        updated_at          = EXCLUDED.updated_at;

    SELECT MAX((el->>'updated_at')::timestamp)
      INTO last_updated
      FROM jsonb_array_elements(p_param_json) AS el;

    IF last_updated IS NOT NULL THEN
        UPDATE mapping.persistent_vars
           SET value = last_updated
         WHERE key = 'last_ticket_updated_at';
    END IF;

    IF NOT p_no_results THEN
        RETURN QUERY
        SELECT
            row_number() OVER ()::integer           AS param_id,
            COALESCE((el->>'track_by')::integer, 0) AS track_by,
            el->>'crud'                             AS crud,
            (el->>'domain_id')::integer             AS domain_id,
            (el->>'ticket_id')::integer             AS ticket_id
        FROM jsonb_array_elements(p_param_json) AS el;
    END IF;
END;
$$;

alter function crud_ticket(jsonb, boolean) owner to xfw3;

