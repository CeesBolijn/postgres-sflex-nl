create function crud_material(p_param_json jsonb, p_no_results boolean DEFAULT false) returns TABLE(param_id integer, track_by integer, crud text, domain_id integer, material_id integer, material_name text)
	language plpgsql
as $$
DECLARE
    rec RECORD;
BEGIN
    CREATE TEMP TABLE param_table (
        param_id    serial PRIMARY KEY,
        row_json    jsonb,   -- raw input element, used as-is (minus crud) for line_json
        track_by    integer,
        crud        text,
        domain_id   integer,
        material_id integer,
        material_name  text,
        substrate_name text
    ) ON COMMIT DROP;

    -- keep the raw element (row_json) alongside the typed columns needed for control flow / return
    INSERT INTO param_table (
        row_json, track_by, crud, domain_id, material_id, material_name, substrate_name
    )
    SELECT
        elem,
        COALESCE(t.track_by, 0),
        t.crud,
        t.domain_id,
        t.material_id,
        t.material_name,
        t.substrate_name
    FROM jsonb_array_elements(p_param_json) AS elem
    CROSS JOIN LATERAL jsonb_to_record(elem) AS t(
        track_by    integer,
        crud        text,
        domain_id   integer,
        material_id integer,
        material_name  text,
        substrate_name text
    );

    FOR rec IN
        SELECT pt.*
        FROM param_table AS pt
        ORDER BY pt.param_id
    LOOP
        IF EXISTS (
            SELECT 1 FROM mapping.material_production_line mpl
            WHERE mpl.material_id = rec.material_id
        ) THEN
            -- shallow merge: new keys overwrite matching keys, untouched keys survive
            UPDATE mapping.material_production_line AS mpl
            SET
                domain_id = rec.domain_id,
                line_json = mpl.line_json || (rec.row_json - 'crud')
            WHERE mpl.material_id = rec.material_id;
        ELSE
            INSERT INTO mapping.material_production_line (
                domain_id, material_id, line_json
            )
            VALUES (
                rec.domain_id,
                rec.material_id,
                rec.row_json - 'crud'
            );
        END IF;
    END LOOP;

    IF NOT p_no_results THEN
        RETURN QUERY
        SELECT pt.param_id, pt.track_by, pt.crud, pt.domain_id,
               pt.material_id, pt.material_name
        FROM param_table pt
        ORDER BY pt.param_id;
    END IF;

END;
$$;

alter function crud_material(jsonb, boolean) owner to xfw3;

