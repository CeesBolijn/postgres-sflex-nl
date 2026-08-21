create function mapping.crud_production_forecast(p_param_json jsonb, p_no_results boolean DEFAULT false) returns TABLE(param_id integer, track_by integer, crud text)
	language plpgsql
as $$
BEGIN
    -- Eén batch inkomende rijen parsen naar een temp-tabel.
    CREATE TEMP TABLE _params ON COMMIT DROP AS
    SELECT
        (row_number() OVER ())::integer AS param_id,
        -- 'date' komt als ISO-string binnen (mssql → JS Date → JSON, UTC). Pak de datum-portie
        -- rechtstreeks uit de string i.p.v. een tz-gevoelige cast, zodat de dag niet verschuift.
        left(t."date", 10)::date        AS "date",
        t.production_line_id, t.production_company_id,
        t.is_holiday,
        t.budget_m2_last_6_weeks, t.actual_m2_last_6_weeks, t.performance_factor,
        t.revenue_forecast, t.m2_forecast, t.production_orders_forecast
    FROM jsonb_to_recordset(p_param_json) AS t(
        "date" text, production_line_id integer, production_company_id integer,
        is_holiday boolean,
        budget_m2_last_6_weeks numeric, actual_m2_last_6_weeks numeric, performance_factor numeric,
        revenue_forecast numeric, m2_forecast numeric, production_orders_forecast numeric
    );

    -- 1) Upsert op de natuurlijke sleutel (PK). Batch-veilig: raakt alleen de sleutels in deze batch.
    INSERT INTO log.production_forecast AS f (
        "date", production_line_id, production_company_id, is_holiday,
        budget_m2_last_6_weeks, actual_m2_last_6_weeks, performance_factor,
        revenue_forecast, m2_forecast, production_orders_forecast)
    SELECT p."date", p.production_line_id, p.production_company_id, p.is_holiday,
        p.budget_m2_last_6_weeks, p.actual_m2_last_6_weeks, p.performance_factor,
        p.revenue_forecast, p.m2_forecast, p.production_orders_forecast
    FROM _params p
    ON CONFLICT ("date", production_line_id, production_company_id) DO UPDATE SET
        is_holiday                 = EXCLUDED.is_holiday,
        budget_m2_last_6_weeks     = EXCLUDED.budget_m2_last_6_weeks,
        actual_m2_last_6_weeks     = EXCLUDED.actual_m2_last_6_weeks,
        performance_factor         = EXCLUDED.performance_factor,
        revenue_forecast           = EXCLUDED.revenue_forecast,
        m2_forecast                = EXCLUDED.m2_forecast,
        production_orders_forecast = EXCLUDED.production_orders_forecast;

    -- 2) Retentie: datums buiten het forecast-venster opruimen.
    --    ⚠️ De grens MOET gelijk zijn aan of OUDER dan de oudste datum die de query teruggeeft.
    --       Staat hij te krap, dan verwijder je in-window data die net is geüpsert (= data-loss).
    DELETE FROM log.production_forecast
    WHERE "date" < (current_date - interval '6 weeks');

    -- 3) Afgeleide data verversen. Faalt dit, dan is dat een probleem van de derived-data laag,
    --    geen reden om een geslaagde forecast-import terug te draaien. Zie GlitchTip 019ff0ed3fa2.
    BEGIN
        PERFORM site.refresh_derived_data();
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'crud_production_forecast: site.refresh_derived_data() faalde (%): %', SQLSTATE, SQLERRM;
    END;

    -- Framework roept aan als `SELECT * FROM ...`, dus een set teruggeven (JobsSync negeert de inhoud).
    IF NOT p_no_results THEN
        RETURN QUERY
        SELECT p.param_id, (p.param_id - 1) AS track_by, 'merge'::text
        FROM _params p ORDER BY p.param_id;
    END IF;
END;
$$;

alter function mapping.crud_production_forecast(jsonb, boolean) owner to xfw3;

