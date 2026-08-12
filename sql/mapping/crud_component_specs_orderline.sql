create function crud_component_specs_orderline(p_param_json jsonb, p_no_results boolean DEFAULT false) returns TABLE(param_id integer, track_by integer, crud text, domain_id integer, production_orderline_id integer)
	language plpgsql
as $$
#variable_conflict use_column
DECLARE
    last_updated_at timestamp;
    rec             record;
    v_sqm           numeric;
    v_resolved_pl   integer;
    v_is_open       boolean;
    v_mpl_id        integer;
    v_ist_seq       integer;
BEGIN
    CREATE TEMP TABLE _params ON COMMIT DROP AS
    SELECT
        row_number() OVER ()::integer AS param_id,
        COALESCE(t.track_by, 0)       AS track_by,
        t.crud, t.domain_id, t.sales_orderline_id,
        t.production_orderline_id, t.production_order_id, t.order_id, t.order_type_id,
        t.material_id, t.first_production_line_id, t.uploader_data_id,
        t.internal_status_code, t.production_order_status, t.production_order_sequence,
        t.logistics_date, t.production_hours, t.customer_id,
        t.product_unit_code, t.product_unit_quantity,
        t.product_width, t.product_height, t.product_amount, t.order_location, COALESCE(t.production_location, t.order_location) production_location,
        t.production_company_id, t.sequence, t.order_number, t.number, t.order_date, t.production_date, t.updated_at,
        t.company_name, t.team_name, t.shipment_date, t.customer_reference, t.product_internal_title,
        t.quality_check, t.binned, t.project_order_checked, t.assembled, t.assembled_production,
        t.allow_rerouting, t.unloading_forklift_available, t.ship_separately, t.order_sequence,
        SUM(t.product_amount) OVER (PARTITION BY t.production_order_id) AS production_order_amount
    FROM jsonb_to_recordset(p_param_json) AS t(
        track_by integer, crud text, domain_id integer, sales_orderline_id integer,
        production_orderline_id integer, production_order_id integer,
        order_id integer, order_type_id integer,
        material_id integer, first_production_line_id integer, uploader_data_id integer,
        internal_status_code text, production_order_status text, production_order_sequence integer,
        logistics_date timestamp, production_hours integer, customer_id integer,
        product_unit_code text, product_unit_quantity numeric,
        product_width numeric, product_height numeric, product_amount numeric, order_location text, production_location text,
        production_company_id integer, sequence integer,
        order_number integer, number text, order_date timestamp, production_date timestamp, updated_at timestamp,
        company_name text, team_name text, shipment_date timestamp, customer_reference text, product_internal_title text,
        quality_check integer, binned integer, project_order_checked boolean, assembled boolean, assembled_production boolean,
        allow_rerouting boolean, unloading_forklift_available boolean, ship_separately boolean, order_sequence integer
    );

    FOR rec IN
        SELECT * FROM _params p ORDER BY p.updated_at ASC NULLS FIRST
    LOOP
        IF rec.crud = 'merge' THEN
            SELECT m.production_line_id INTO v_mpl_id
            FROM mapping.material_production_line m
            WHERE m.material_id = rec.material_id
            ORDER BY m.production_line_id ASC
            LIMIT 1;

            SELECT ist.sequence INTO v_ist_seq
            FROM mapping.internal_status ist
            WHERE ist.code = rec.internal_status_code;

            v_sqm := CASE
                WHEN rec.material_id IN (352, 353, 350, 351, 349, 348, 380, 107) THEN 0
                WHEN rec.first_production_line_id IS NULL THEN 0
                WHEN rec.first_production_line_id IN (11, 6, 1) THEN 0
                ELSE (rec.product_width / 100.0) * (rec.product_height / 100.0) * rec.product_amount
            END;

            v_resolved_pl := CASE
                WHEN rec.material_id = 355 THEN rec.first_production_line_id
                WHEN rec.first_production_line_id IN (6, 11) THEN rec.first_production_line_id
                WHEN v_mpl_id IS NULL THEN rec.first_production_line_id
                ELSE v_mpl_id
            END;

            v_is_open := COALESCE(v_ist_seq, 0) < 920;

            INSERT INTO mapping.component_specs (
                domain_id, sales_orderline_id, production_orderline_id, production_order_id, order_id, order_type_id,
                material_id, first_production_line_id, uploader_data_id, customer_id,
                internal_status_code, production_order_status, production_order_sequence,
                logistics_date, product_unit_code, product_unit_quantity, order_location, production_location,
                product_width, product_height, product_amount, production_hours,
                production_company_id, sequence, order_number, number, order_date, production_date,
                sqm, resolved_production_line_id, is_open, orderline_updated_at,
                company_name, team_name, shipment_date, customer_reference, product_internal_title,
                quality_check, binned, project_order_checked, assembled, assembled_production,
                allow_rerouting, unloading_forklift_available, ship_separately, order_sequence, nest_date,
                production_order_amount
            ) VALUES (
                rec.domain_id, rec.sales_orderline_id, rec.production_orderline_id, rec.production_order_id, rec.order_id, rec.order_type_id,
                rec.material_id, rec.first_production_line_id, rec.uploader_data_id, rec.customer_id,
                rec.internal_status_code, rec.production_order_status, rec.production_order_sequence,
                rec.logistics_date, rec.product_unit_code, rec.product_unit_quantity, rec.order_location, rec.production_location,
                rec.product_width, rec.product_height, rec.product_amount, rec.production_hours,
                rec.production_company_id, rec.sequence, rec.order_number, rec.number, rec.order_date, rec.production_date,
                v_sqm, v_resolved_pl, v_is_open, rec.updated_at,
                rec.company_name, rec.team_name, rec.shipment_date, rec.customer_reference, rec.product_internal_title,
                rec.quality_check, rec.binned, rec.project_order_checked, rec.assembled, rec.assembled_production,
                rec.allow_rerouting, rec.unloading_forklift_available, rec.ship_separately, rec.order_sequence,
                mapping.calculate_nest_date(rec.order_date::date, rec.production_hours), rec.production_order_amount
            )
            ON CONFLICT ON CONSTRAINT uq_component_specs_orderline_id
            DO UPDATE SET
                domain_id                   = EXCLUDED.domain_id,
                sales_orderline_id          = EXCLUDED.sales_orderline_id,
                production_order_id         = EXCLUDED.production_order_id,
                order_id                    = EXCLUDED.order_id,
                order_type_id                = EXCLUDED.order_type_id,
                material_id                 = EXCLUDED.material_id,
                first_production_line_id    = EXCLUDED.first_production_line_id,
                uploader_data_id            = EXCLUDED.uploader_data_id,
                customer_id                 = EXCLUDED.customer_id,
                internal_status_code        = EXCLUDED.internal_status_code,
                production_order_status     = EXCLUDED.production_order_status,
                production_order_sequence   = EXCLUDED.production_order_sequence,
                logistics_date              = EXCLUDED.logistics_date,
                product_unit_code           = EXCLUDED.product_unit_code,
                product_unit_quantity        = EXCLUDED.product_unit_quantity,
                production_hours            = EXCLUDED.production_hours,
                order_location              = EXCLUDED.order_location,
                production_location         = EXCLUDED.production_location,
                product_width               = EXCLUDED.product_width,
                product_height              = EXCLUDED.product_height,
                product_amount              = EXCLUDED.product_amount,
                production_company_id       = EXCLUDED.production_company_id,
                sequence                    = EXCLUDED.sequence,
                order_number                = EXCLUDED.order_number,
                number                      = EXCLUDED.number,
                order_date                  = EXCLUDED.order_date,
                production_date             = EXCLUDED.production_date,
                sqm                         = EXCLUDED.sqm,
                resolved_production_line_id = EXCLUDED.resolved_production_line_id,
                is_open                     = EXCLUDED.is_open,
                orderline_updated_at        = EXCLUDED.orderline_updated_at,
                company_name                = EXCLUDED.company_name,
                team_name                   = EXCLUDED.team_name,
                shipment_date               = EXCLUDED.shipment_date,
                customer_reference          = EXCLUDED.customer_reference,
                product_internal_title      = COALESCE(EXCLUDED.product_internal_title, mapping.component_specs.product_internal_title),
                quality_check               = EXCLUDED.quality_check,
                binned                      = EXCLUDED.binned,
                project_order_checked       = EXCLUDED.project_order_checked,
                assembled                   = EXCLUDED.assembled,
                assembled_production        = EXCLUDED.assembled_production,
                allow_rerouting             = EXCLUDED.allow_rerouting,
                unloading_forklift_available = EXCLUDED.unloading_forklift_available,
                ship_separately             = EXCLUDED.ship_separately,
                order_sequence              = EXCLUDED.order_sequence,
                nest_date                   = EXCLUDED.nest_date,
                production_order_amount     = EXCLUDED.production_order_amount
            -- skip the write entirely when none of the fields that actually change have changed;
            -- avoids generating a dead tuple for a no-op update
            WHERE mapping.component_specs.internal_status_code    IS DISTINCT FROM EXCLUDED.internal_status_code
               OR mapping.component_specs.production_order_status IS DISTINCT FROM EXCLUDED.production_order_status
               OR mapping.component_specs.production_date         IS DISTINCT FROM EXCLUDED.production_date
               OR mapping.component_specs.binned                  IS DISTINCT FROM EXCLUDED.binned
               OR mapping.component_specs.assembled               IS DISTINCT FROM EXCLUDED.assembled
               OR mapping.component_specs.is_open                 IS DISTINCT FROM EXCLUDED.is_open
               OR mapping.component_specs.order_sequence          IS DISTINCT FROM EXCLUDED.order_sequence;

            -- only touch is_dibond_override when the computed value actually differs from what's stored;
            -- in practice this is true only on first classification, so this update is almost always skipped
            WITH computed_dibond AS (
                SELECT
                    cs.production_orderline_id,
                    EXISTS (
                        SELECT 1
                        FROM mapping.status_log sl
                        JOIN mapping.internal_status i
                            ON i.internal_status_id = (sl.line_json->>'update_internal_status_id')::int
                        JOIN mapping.material_production_line mpl
                            ON mpl.material_id = cs.material_id
                           AND mpl.line_json->>'name' = 'Dibond 3mm QuaPro Permanent'
                        WHERE sl.object_id = cs.production_orderline_id
                          AND i.sequence = 797
                    ) AS new_is_dibond_override
                FROM mapping.component_specs cs
                WHERE cs.production_orderline_id = rec.production_orderline_id
            )
            UPDATE mapping.component_specs cs
            SET is_dibond_override = cd.new_is_dibond_override
            FROM computed_dibond cd
            WHERE cs.production_orderline_id = cd.production_orderline_id
              AND cs.is_dibond_override IS DISTINCT FROM cd.new_is_dibond_override;
        END IF;
    END LOOP;

    -- Enrich resources_json for processed orderlines
    -- batched / ripping / ripped / printed all map to print_production_unit_id
    -- cut maps to cut_production_unit_id
    -- only write when the computed uids actually differ, since this rarely changes once set
--     UPDATE mapping.component_specs cs
--     SET resource_uids = r.uids
--     FROM (
--         SELECT
--             (sp.single_product_json->>'production_orderline_id')::int AS production_orderline_id,
--             array_agg(DISTINCT res.resource_uid) AS uids
--         FROM legacy.single_product sp
--         JOIN legacy.nest  n ON n.nest_id  = sp.nest_id
--         JOIN legacy.batch b ON b.batch_uid = n.batch_uid
--         CROSS JOIN LATERAL (VALUES
--             (b.batch_json->>'print_production_unit_id'),
--             (b.batch_json->>'cut_production_unit_id')
--             -- + coater / laminator / finishing-velden hier toevoegen
--         ) AS x(pv2)
--         JOIN relation.resource res
--             ON (res.resource_json->>'pv2_id') = x.pv2     -- pv2 -> uid, één keer bij write
--         WHERE x.pv2 IS NOT NULL
--         GROUP BY (sp.single_product_json->>'production_orderline_id')::int
--     ) r
--     WHERE cs.production_orderline_id = r.production_orderline_id
--       AND cs.resource_uids IS DISTINCT FROM r.uids;

    SELECT MAX(p.updated_at) INTO last_updated_at FROM _params p;

    IF last_updated_at IS NOT NULL THEN
        UPDATE mapping.persistent_vars
        SET value = (last_updated_at - INTERVAL '2 minutes')::text
        WHERE key = 'last_production_orderline_updated_at';
    END IF;
    
    PERFORM mapping.create_spec_unit_manifest(
        (SELECT array_agg(DISTINCT production_orderline_id)
         FROM   _params pt)
    );

    IF NOT p_no_results THEN
        RETURN QUERY
        SELECT p.param_id, p.track_by, p.crud, p.domain_id, p.production_orderline_id
        FROM _params p
        ORDER BY p.param_id;
    END IF;
END;
$$;

alter function crud_component_specs_orderline(jsonb, boolean) owner to xfw3;

