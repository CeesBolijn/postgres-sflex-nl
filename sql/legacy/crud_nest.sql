create function legacy.crud_nest(p_param_json jsonb, p_no_results boolean DEFAULT false) returns TABLE(param_id integer, track_by integer, crud text, domain_id integer, batch_id bigint, nest_id bigint, nest_counter integer, reproduced_counter integer, nest_name text, amount integer, width numeric, height numeric, nest_json jsonb, sort_order integer, status jsonb, possible_states bigint, possible_multiple_states bigint)
	language plpgsql
as $$
DECLARE
    last_updated_at timestamp;
    rec             record;
    v_batch_uid     bigint;
BEGIN
    CREATE TEMP TABLE param_table ON COMMIT DROP AS
    SELECT
        row_number() OVER ()::integer     AS param_id,
        COALESCE(te.track_by, 0)          AS track_by,
        te.crud,
        te.domain_id,
        te.batch_id,
        te.nest_id,
        COALESCE(te.nest_counter, 1)      AS nest_counter,
        COALESCE(te.reproduced_counter, 0) AS reproduced_counter,
        te.nest_name,
        te.amount,
        te.width::numeric(10,1)           AS width,
        te.height::numeric(10,1)          AS height,
        t.element                         AS nest_json,
        te.sort_order,
        te.status,
        te.possible_states,
        te.possible_multiple_states,
        te.nest_date,
        te.updated_at
    FROM jsonb_array_elements(p_param_json) AS t(element)
    CROSS JOIN LATERAL jsonb_to_record(t.element) AS te(
        track_by                 integer,
        crud                     text,
        domain_id                integer,
        batch_id                 bigint,
        nest_id                  bigint,
        nest_counter             integer,
        reproduced_counter       integer,
        nest_name                text,
        amount                   integer,
        width                    numeric,
        height                   numeric,
        sort_order               integer,
        status                   jsonb,
        possible_states          bigint,
        possible_multiple_states bigint,
        nest_date                timestamptz,
        updated_at               timestamptz
    );

    FOR rec IN
        SELECT * FROM param_table pt ORDER BY pt.updated_at ASC NULLS FIRST
    LOOP
        SELECT b.batch_uid INTO v_batch_uid
        FROM legacy.batch b
        WHERE b.batch_id = rec.batch_id;

        IF rec.crud IN ('create','merge') THEN
            INSERT INTO legacy.nest (
                batch_uid, domain_id, nest_id, nest_counter, reproduced_counter,
                nest_name, amount, width, height, nest_json, sort_order,
                status_json, possible_states, possible_multiple_states, nested_at, updated_at
            ) VALUES (
                v_batch_uid, rec.domain_id, rec.nest_id, rec.nest_counter, rec.reproduced_counter,
                rec.nest_name, rec.amount, rec.width, rec.height,
                -- never insert a bare NULL into nest_json
                COALESCE(rec.nest_json, '{}'::jsonb),
                rec.sort_order,
                rec.status, rec.possible_states, rec.possible_multiple_states, rec.nest_date, rec.updated_at
            )
            ON CONFLICT ON CONSTRAINT uq_nest_id DO UPDATE
                SET batch_uid                = EXCLUDED.batch_uid,
                    nest_name                = EXCLUDED.nest_name,
                    amount                   = EXCLUDED.amount,
                    width                    = EXCLUDED.width,
                    height                   = EXCLUDED.height,
                    -- merge instead of replace: keys not present in the incoming
                    -- payload (e.g. commercial_waste_percentage, which is
                    -- computed elsewhere and not part of this event) are kept.
                    -- Incoming keys still win over existing ones on conflict.
                    nest_json                = COALESCE(legacy.nest.nest_json, '{}'::jsonb)
                                                || COALESCE(EXCLUDED.nest_json, '{}'::jsonb),
                    sort_order               = EXCLUDED.sort_order,
                    status_json              = EXCLUDED.status_json,
                    possible_states          = EXCLUDED.possible_states,
                    possible_multiple_states = EXCLUDED.possible_multiple_states,
                    nested_at                = EXCLUDED.nested_at,
                    updated_at               = EXCLUDED.updated_at;

            -- insert into legacy.nest_log when a nest is created (initial 'ripped' entry, full amount)
            INSERT INTO legacy.nest_log
                (nest_id, from_status_sequence, to_status_sequence, amount, remaining_impact_delta, resource_uids, moved_at)
            SELECT
                n.nest_id,
                NULL,
                l.sequence,
                n.amount,
                NULL,
                '{}'::text[],
                now()
            FROM legacy.nest n,
                 relation.lookup rl,
                 jsonb_to_recordset(rl.lookup_json) AS l(step text, sequence int)
            WHERE n.nest_id = rec.nest_id
              AND rl.lookup = 'lookup_step_category'
              AND l.step = 'ripped';

        ELSIF rec.crud = 'update' THEN
            UPDATE legacy.nest n
            SET
                batch_uid                = v_batch_uid,
                -- merge instead of replace, same reasoning as the create/merge branch above
                nest_json                = COALESCE(n.nest_json, '{}'::jsonb)
                                            || COALESCE(rec.nest_json, '{}'::jsonb),
                sort_order               = rec.sort_order,
                status_json              = rec.status,
                possible_states          = rec.possible_states,
                possible_multiple_states = rec.possible_multiple_states,
                nested_at                = rec.nest_date,
                updated_at               = rec.updated_at
            WHERE n.nest_id = rec.nest_id;
        END IF;
    END LOOP;

    UPDATE legacy.nest n
    SET batch_uid = b.batch_uid
    FROM legacy.batch b
    WHERE n.batch_uid IS NULL
      AND b.batch_id = (n.nest_json ->> 'batch_id')::integer;

    -- ── nest → lane item (docs/nest-planning-lane-items.md §3) ─────────
    -- Every nest hangs on a lane item of the material-resource-plan of its
    -- day: plan → plan_lane → lane (the material lane) → lane_item. The
    -- item picked is the latest one starting at or before the nest moment
    -- (the stamped items are 0-duration moments, so a covering-window match
    -- would never hit), else the first of the day. Durations are never
    -- stored here: the boards derive them at read time — nests from
    -- width × height × sum(amount), the future from the aggregate and the
    -- material sizes in line_json.specs.
    CREATE TEMP TABLE nest_link ON COMMIT DROP AS
    WITH payload AS (
        SELECT pt.nest_id, pt.sort_order,
               (n.nest_json ->> 'material_id')::integer        AS material_id,
               (n.nest_json ->> 'production_line_id')::integer AS production_line_id,
               (COALESCE(pt.nest_date, n.nested_at) AT TIME ZONE 'Europe/Amsterdam')::date AS plan_date,
               extract(epoch FROM (COALESCE(pt.nest_date, n.nested_at) AT TIME ZONE 'Europe/Amsterdam')::time)::integer AS nest_seconds,
               lower(COALESCE(n.nest_json ->> 'status', '')) LIKE 'cancel%' AS is_cancelled
        FROM param_table pt
        JOIN legacy.nest n ON n.nest_id = pt.nest_id
        WHERE pt.crud IN ('create', 'merge', 'update')
    )
    SELECT p.nest_id, p.sort_order, p.nest_seconds, p.is_cancelled,
           lane.lane_id, slot.lane_item_id
    FROM payload p
    LEFT JOIN relation.production_line prl ON prl.line_id = p.production_line_id
    LEFT JOIN LATERAL (
        SELECT ap.plan_id
        FROM action.plan ap
        WHERE ap.plan_date = p.plan_date
          AND ap.type = 'material-resource-plan'
          AND (prl.line_type IS NULL OR ap.line_type = prl.line_type)
        ORDER BY ap.plan_id DESC
        LIMIT 1
    ) tp ON true
    LEFT JOIN LATERAL (
        -- the material lane of that plan, through the material pattern:
        -- the nest side keys on material_id — the imposition group link
        -- (imposition_group_lane_item) is the future side of the board
        SELECT l.lane_id
        FROM action.plan_lane apl
        JOIN action.lane l ON l.lane_id = apl.lane_id
        JOIN mock.material_resource_plan_lane mrpl ON mrpl.lane_id = l.lane_id
        JOIN mock.material_resource_plan m ON m.material_resource_plan_id = mrpl.material_resource_plan_id
        WHERE apl.plan_id = tp.plan_id
          AND m.material_id = p.material_id
        LIMIT 1
    ) lane ON true
    LEFT JOIN LATERAL (
        SELECT li.lane_item_id
        FROM action.lane_item li
        WHERE li.lane_id = lane.lane_id
          AND li.level = 0
        ORDER BY (COALESCE(li.start_offset_in_seconds, 0) <= p.nest_seconds) DESC,
                 CASE WHEN COALESCE(li.start_offset_in_seconds, 0) <= p.nest_seconds
                      THEN -COALESCE(li.start_offset_in_seconds, 0)
                      ELSE COALESCE(li.start_offset_in_seconds, 0) END
        LIMIT 1
    ) slot ON true;

    -- lane found but no lane item at all: create one for this nest
    INSERT INTO action.lane_item
        (lane_id, sort_order, start_offset_in_seconds, no_split, level, source, source_ref)
    SELECT ns.lane_id, -1 * ns.nest_id, ns.nest_seconds, true, 0, 'nest', ns.nest_id::text
    FROM nest_link ns
    WHERE ns.lane_item_id IS NULL
      AND ns.lane_id IS NOT NULL
      AND NOT ns.is_cancelled
    ON CONFLICT ON CONSTRAINT lane_item_source_ref_uq DO NOTHING;

    -- replace the material-lane links of the payload nests as a set; the
    -- pv2 machine links belong to action.crud_object and stay untouched.
    -- Cancelled nests only lose their link. No plan or lane for the day:
    -- no link, never an invented lane — the backfill catches it later.
    DELETE FROM action.nest_lane_item nli
    USING action.lane_item li
    WHERE nli.lane_item_id = li.lane_item_id
      AND li.source IN ('material-plan', 'nest')
      AND nli.nest_id IN (SELECT ns.nest_id FROM nest_link ns);

    INSERT INTO action.nest_lane_item (nest_id, lane_item_id, sort_order)
    SELECT ns.nest_id,
           COALESCE(ns.lane_item_id, own.lane_item_id),
           ns.sort_order
    FROM nest_link ns
    LEFT JOIN action.lane_item own
           ON own.source = 'nest' AND own.source_ref = ns.nest_id::text
    WHERE NOT ns.is_cancelled
      AND COALESCE(ns.lane_item_id, own.lane_item_id) IS NOT NULL
    ON CONFLICT DO NOTHING;

    SELECT MAX(pt.updated_at) INTO last_updated_at
    FROM param_table pt;

    IF last_updated_at IS NOT NULL THEN
        UPDATE mapping.persistent_vars
        SET value = last_updated_at - INTERVAL '2 minutes'
        WHERE key = 'last_nest_updated_at';
    END IF;

    IF NOT p_no_results THEN
        RETURN QUERY
        SELECT pt.param_id, pt.track_by, pt.crud, pt.domain_id,
               pt.batch_id, pt.nest_id, pt.nest_counter, pt.reproduced_counter,
               pt.nest_name, pt.amount, pt.width, pt.height, pt.nest_json,
               pt.sort_order, pt.status, pt.possible_states, pt.possible_multiple_states
        FROM param_table pt
        ORDER BY pt.param_id;
    END IF;
END;
$$;

alter function legacy.crud_nest(jsonb, boolean) owner to xfw3;

