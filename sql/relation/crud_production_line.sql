create function relation.crud_production_line(p_param_json jsonb, p_no_results boolean DEFAULT false) returns TABLE(param_id integer, track_by integer, crud text, domain_id integer, production_line_id integer, name text)
	language plpgsql
as $$
DECLARE
    rec RECORD;
BEGIN
    CREATE TEMP TABLE param_table (
        param_id           serial PRIMARY KEY,
        track_by           integer,
        crud               text,
        domain_id          integer,
        production_line_id integer,
        production_line_name text
    ) ON COMMIT DROP;

    INSERT INTO param_table (
        track_by, crud, domain_id, production_line_id, production_line_name
    )
    SELECT
        COALESCE(t.track_by, 0),
        t.crud,
        t.domain_id,
        t.production_line_id,
        t.production_line_name
    FROM jsonb_to_recordset(p_param_json) AS t(
        track_by           integer,
        crud               text,
        domain_id          integer,
        production_line_id integer,
        production_line_name               text
    );

    FOR rec IN
        SELECT pt.param_id, pt.domain_id, pt.production_line_id
        FROM param_table AS pt
        ORDER BY pt.param_id
    LOOP
        IF NOT EXISTS (
            SELECT 1
            FROM relation.production_line pl
            WHERE pl.domain_id = rec.domain_id
              AND line_id = rec.production_line_id
        ) THEN
            INSERT INTO relation.production_line (
                line_id, domain_id, line, line_json
            )
            SELECT
                pt.production_line_id,
                pt.domain_id,
                pt.production_line_name,
                jsonb_build_object(
                    'production_line_id', pt.production_line_id,
                    'production_line_name', pt.production_line_name
                )
            FROM param_table AS pt
            WHERE pt.param_id = rec.param_id;
        ELSE
            UPDATE relation.production_line AS pl
            SET
                line      = pt.production_line_name,
                line_json = pl.line_json::jsonb || jsonb_build_object(
                    'production_line_id', pt.production_line_id,
                    'production_line_name', pt.production_line_name,
                    'code', public.to_kebab(pt.production_line_name)
                )
            FROM param_table AS pt
            WHERE pl.domain_id = pt.domain_id
              AND line_id = pt.production_line_id
              AND pt.param_id = rec.param_id;
        END IF;
    END LOOP;

    IF NOT p_no_results THEN
        RETURN QUERY
        SELECT pt.param_id, pt.track_by, pt.crud, pt.domain_id,
               pt.production_line_id, pt.production_line_name
        FROM param_table pt
        ORDER BY pt.param_id;
    END IF;
END;
$$;

alter function relation.crud_production_line(jsonb, boolean) owner to xfw3;

