create function legacy.crud_batch(p_param_json jsonb, p_no_results boolean DEFAULT false) returns TABLE(param_id integer, track_by integer, crud text, domain_id integer, batch_id bigint, batch_counter integer, batch_at timestamp with time zone, batch_name text, x_bom text, width numeric, height numeric, batch_json jsonb, status jsonb, year_week_day_timeslot_index integer)
	language plpgsql
as $$
    #variable_conflict use_column
DECLARE
    last_updated_at timestamp;
    rec             record;
BEGIN
    CREATE TEMP TABLE param_table ON COMMIT DROP AS
    SELECT
        row_number() OVER ()::integer     AS param_id,
        COALESCE(te.track_by, 0)          AS track_by,
        te.crud,
        te.domain_id,
        te.batch_id,
        COALESCE(te.batch_counter, 1)     AS batch_counter,
        te.batch_at,
        te.name                           AS batch_name,
        te.x_bom,
        te.width::numeric(10,1)           AS width,
        te.height::numeric(10,1)          AS height,
        t.element                         AS batch_json,
        te.status,
        te.year_week_day_timeslot_index,
        te.updated_at
    FROM jsonb_array_elements(p_param_json) AS t(element)
    CROSS JOIN LATERAL jsonb_to_record(t.element) AS te(
        track_by                     integer,
        crud                         text,
        domain_id                    integer,
        batch_id                     bigint,
        batch_counter                integer,
        batch_at                     timestamptz,
        name                         text,
        x_bom                        text,
        width                        numeric,
        height                       numeric,
        status                       jsonb,
        year_week_day_timeslot_index integer,
        updated_at                   timestamptz
    );

    FOR rec IN
        SELECT * FROM param_table pt ORDER BY pt.updated_at ASC NULLS FIRST
    LOOP
        -- Serialiseer parallelle calls op dezelfde batch_id
        PERFORM pg_advisory_xact_lock(hashtext('crud_batch'), rec.batch_id::int);

        IF rec.crud = 'create' THEN
            INSERT INTO legacy.batch (
                domain_id, batch_id, batch_counter, batch_at, batch_name,
                x_bom, width, height, batch_json, status
            ) VALUES (
                rec.domain_id, rec.batch_id, rec.batch_counter, rec.batch_at, rec.batch_name,
                rec.x_bom, rec.width, rec.height, rec.batch_json, rec.status
            )
            ON CONFLICT ON CONSTRAINT uq_batch_id DO NOTHING;

        ELSIF rec.crud = 'merge' THEN
            INSERT INTO legacy.batch (
                domain_id, batch_id, batch_counter, batch_at, batch_name,
                x_bom, width, height, batch_json, status, updated_at
            ) VALUES (
                rec.domain_id, rec.batch_id, rec.batch_counter, rec.batch_at, rec.batch_name,
                rec.x_bom, rec.width, rec.height, rec.batch_json, rec.status, rec.updated_at
            )
            ON CONFLICT ON CONSTRAINT uq_batch_id DO UPDATE
                SET batch_name = EXCLUDED.batch_name,
                    x_bom      = EXCLUDED.x_bom,
                    width      = EXCLUDED.width,
                    height     = EXCLUDED.height,
                    batch_json = COALESCE(legacy.batch.batch_json, '{}'::jsonb)
                                 || jsonb_strip_nulls(EXCLUDED.batch_json),
                    status     = EXCLUDED.status,
                    updated_at = EXCLUDED.updated_at;
                    
        ELSIF rec.crud = 'update' THEN
            UPDATE legacy.batch b
            SET
                status     = rec.status,
                batch_json = COALESCE(b.batch_json, '{}'::jsonb)
                             || jsonb_strip_nulls(rec.batch_json),
                x_bom      = rec.x_bom,
                width      = rec.width,
                height     = rec.height,
                updated_at = rec.updated_at
            WHERE b.batch_id = rec.batch_id;
        END IF;

        -- Denormaliseer print/cut unit-id's naar single_product_json
        -- ALLEEN als de relevante velden in deze batch_json zitten,
        -- EN ALLEEN voor SP-rijen waar de waarde daadwerkelijk verandert.
        IF rec.crud IN ('create', 'merge', 'update')
           AND (rec.batch_json ? 'print_production_unit_id'
                OR rec.batch_json ? 'cut_production_unit_id')
        THEN
            UPDATE legacy.single_product sp
            SET single_product_json = sp.single_product_json
                || jsonb_strip_nulls(jsonb_build_object(
                    'print_production_unit_id', (b.batch_json->>'print_production_unit_id')::integer,
                    'cut_production_unit_id',   (b.batch_json->>'cut_production_unit_id')::integer
                ))
            FROM legacy.nest n
            JOIN legacy.batch b ON b.batch_id = (n.nest_json->>'batch_id')::int
            WHERE b.batch_id = rec.batch_id
              AND sp.nest_id = n.nest_id
              AND sp.single_product_json IS DISTINCT FROM (
                  sp.single_product_json
                  || jsonb_strip_nulls(jsonb_build_object(
                      'print_production_unit_id', (b.batch_json->>'print_production_unit_id')::integer,
                      'cut_production_unit_id',   (b.batch_json->>'cut_production_unit_id')::integer
                  ))
              );
        END IF;
    END LOOP;

    SELECT MAX(pt.updated_at) INTO last_updated_at
    FROM param_table pt;

    IF last_updated_at IS NOT NULL THEN
        UPDATE mapping.persistent_vars
        SET value = last_updated_at - INTERVAL '2 minutes'
        WHERE key = 'last_batch_updated_at';
    END IF;

    IF NOT p_no_results THEN
        RETURN QUERY
        SELECT pt.param_id, pt.track_by, pt.crud, pt.domain_id,
               pt.batch_id, pt.batch_counter, pt.batch_at, pt.batch_name,
               pt.x_bom, pt.width, pt.height, pt.batch_json, pt.status,
               pt.year_week_day_timeslot_index
        FROM param_table pt
        ORDER BY pt.param_id;
    END IF;
END;
$$;

alter function legacy.crud_batch(jsonb, boolean) owner to xfw3;

