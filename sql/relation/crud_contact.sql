create function crud_contact(p_param_json jsonb, p_no_results boolean DEFAULT false) returns TABLE(param_id integer, track_by integer, crud character varying, company_id integer, employee_id integer, first_name character varying, last_name character varying, last_name_prefix character varying, gender character varying, email character varying, config jsonb)
	language plpgsql
as $$
DECLARE
    v_param_id    INTEGER;
    v_crud        VARCHAR(100);
    v_employee_id INTEGER;
BEGIN
    -- Create temporary table for parameters
    DROP TABLE IF EXISTS temp_param_table;
    CREATE TEMP TABLE temp_param_table
    (
        param_id         SERIAL,
        track_by         INTEGER,
        crud             VARCHAR(100),
        company_id       INTEGER,
        employee_id      INTEGER,
        first_name       VARCHAR(100),
        last_name        VARCHAR(100),
        last_name_prefix VARCHAR(50),
        gender           VARCHAR(50),
        email            VARCHAR(100),
        config           JSONB
    );

    -- Populate from JSON
    INSERT INTO temp_param_table(track_by, crud, employee_id, company_id, first_name, last_name, last_name_prefix,
                                 gender, email, config)
    SELECT (item ->> 'trackBy')::INTEGER,
           item ->> 'crud',
           (item ->> 'employeeId')::INTEGER,
           (item ->> 'companyId')::INTEGER,
           item ->> 'firstName',
           item ->> 'lastName',
           item ->> 'lastNamePrefix',
           item ->> 'gender',
           item ->> 'email',
           item
    FROM jsonb_array_elements(p_param_json) AS item;

    -- Process mutations with cursor
    FOR v_param_id, v_crud, v_employee_id IN
        SELECT pt.param_id, pt.crud, pt.employee_id
        FROM temp_param_table pt
        ORDER BY pt.crud
        LOOP
            IF v_crud = 'create-from-dyflexis' THEN
                IF NOT EXISTS (SELECT 1
                               FROM relation.contact c
                               WHERE (c.config ->> 'employeeId')::INTEGER = v_employee_id) THEN
                    INSERT INTO relation.contact(company_id, first_name, insertion, last_name, gender, email, config, roles)
                    SELECT pt.company_id,
                           pt.first_name,
                           pt.last_name_prefix,
                           pt.last_name,
                           CASE WHEN pt.gender = 'male' THEN 1 ELSE 0 END,
                           pt.email,
                           pt.config,
                           '["user", "employee"]' -- When an account is created, by default it's an employee and user by Dyflexis
                    FROM temp_param_table pt
                    WHERE pt.param_id = v_param_id;
                END IF;
            END IF;
        END LOOP;

    -- Return results unless suppressed
    IF NOT p_no_results THEN
        RETURN QUERY
            SELECT pt.param_id,
                   pt.track_by,
                   pt.crud,
                   pt.company_id,
                   pt.employee_id,
                   pt.first_name,
                   pt.last_name,
                   pt.last_name_prefix,
                   pt.gender,
                   pt.email,
                   pt.config
            FROM temp_param_table pt;
    END IF;

    DROP TABLE IF EXISTS temp_param_table;
END;
$$;

alter function crud_contact(jsonb, boolean) owner to xfw3;

