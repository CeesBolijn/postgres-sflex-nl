create function mapping.get_sitrep(p_model text DEFAULT NULL::text, p_models text[] DEFAULT NULL::text[], p_production_line_id integer DEFAULT NULL::integer) returns TABLE(content jsonb, nav jsonb, bucket_index integer, bucket_date date, production_line jsonb, order_count bigint, order_open bigint, order_done bigint, order_pct_done numeric, order_printed bigint, order_pct_printed numeric, order_cut bigint, order_pct_cut numeric, customer_count bigint, sqm_total numeric, sqm_open numeric, sqm_done numeric, sqm_pct_done numeric, sqm_printed numeric, sqm_pct_printed numeric, sqm_cut numeric, sqm_pct_cut numeric, current_time_epoch numeric, sqm_color_index numeric, order_color_index numeric)
	stable
	language plpgsql
as $$
#variable_conflict use_column
DECLARE
    v_models     text[] := COALESCE(p_models, ARRAY[p_model]);
    v_buckets    jsonb;
    v_prod_lines jsonb;
BEGIN
    SELECT lookup_json INTO v_buckets
      FROM mapping.lookup
     WHERE lookup = 'lookup_sitrep';

    SELECT lookup_json INTO v_prod_lines
      FROM relation.lookup
     WHERE lookup = 'lookup_production_line';

    RETURN QUERY
    WITH
    prod_lines AS (
        SELECT el->>'code' AS code, el->'i18n' AS i18n
        FROM jsonb_array_elements(v_prod_lines) AS el
    ),
    bucketed AS (
        SELECT
            CASE v.bucket
                WHEN 'overdue'            THEN 0
                WHEN 'today'              THEN 1
                WHEN 'tomorrow'           THEN 2
                WHEN 'day_after_tomorrow' THEN 3
            END                 AS bucket_index,
            CASE v.bucket
                WHEN 'overdue'            THEN v_buckets->0->'i18n'
                WHEN 'today'              THEN v_buckets->1->'i18n'
                WHEN 'tomorrow'           THEN v_buckets->2->'i18n'
                WHEN 'day_after_tomorrow' THEN v_buckets->3->'i18n'
            END                 AS content,
            CASE v.bucket
                WHEN 'overdue'            THEN v_buckets->0->'nav'
                WHEN 'today'              THEN v_buckets->1->'nav'
                WHEN 'tomorrow'           THEN v_buckets->2->'nav'
                WHEN 'day_after_tomorrow' THEN v_buckets->3->'nav'
            END                 AS nav,
            v.bucket_date,
            pl_i18n.i18n        AS effective_line,
            v.order_id,
            v.customer_id,
            v.sqm,
            v.is_open,
            v.status_sequence
        FROM mapping.v_production_orderlines v
        LEFT JOIN relation.production_line rpl ON rpl.line_id = v.effective_line_id
        LEFT JOIN prod_lines pl_i18n ON pl_i18n.code = rpl.line_json::jsonb->>'code'
        WHERE v.bucket IS NOT NULL
          AND v.effective_model = ANY(v_models)
          AND (p_production_line_id IS NULL OR v.effective_line_id = p_production_line_id)
    ),
    aggregated AS (
        SELECT
            b.content,
            b.nav,
            b.bucket_index,
            b.bucket_date,
            b.effective_line                                                                        AS production_line,
            COUNT(DISTINCT b.order_id)                                                             AS order_count,
            COUNT(DISTINCT b.order_id) FILTER (WHERE b.is_open)                                   AS order_open,
            COUNT(DISTINCT b.order_id) FILTER (WHERE NOT b.is_open)                               AS order_done,
            CASE WHEN COUNT(DISTINCT b.order_id) = 0 THEN 0
                 ELSE ROUND(COUNT(DISTINCT b.order_id) FILTER (WHERE NOT b.is_open)::numeric
                          / COUNT(DISTINCT b.order_id) * 100, 1) END                              AS order_pct_done,
            COUNT(DISTINCT b.order_id) FILTER (WHERE b.status_sequence >= 700)                    AS order_printed,
            CASE WHEN COUNT(DISTINCT b.order_id) = 0 THEN 0
                 ELSE ROUND(COUNT(DISTINCT b.order_id) FILTER (WHERE b.status_sequence >= 700)::numeric
                          / COUNT(DISTINCT b.order_id) * 100, 1) END                              AS order_pct_printed,
            COUNT(DISTINCT b.order_id) FILTER (WHERE b.status_sequence >= 801)                    AS order_cut,
            CASE WHEN COUNT(DISTINCT b.order_id) = 0 THEN 0
                 ELSE ROUND(COUNT(DISTINCT b.order_id) FILTER (WHERE b.status_sequence >= 801)::numeric
                          / COUNT(DISTINCT b.order_id) * 100, 1) END                              AS order_pct_cut,
            COUNT(DISTINCT b.customer_id)                                                          AS customer_count,
            COALESCE(SUM(b.sqm), 0)                                                               AS sqm_total,
            COALESCE(SUM(b.sqm) FILTER (WHERE b.is_open), 0)                                      AS sqm_open,
            COALESCE(SUM(b.sqm) FILTER (WHERE NOT b.is_open), 0)                                  AS sqm_done,
            CASE WHEN COALESCE(SUM(b.sqm), 0) = 0 THEN 0
                 ELSE ROUND(COALESCE(SUM(b.sqm) FILTER (WHERE NOT b.is_open), 0)
                          / SUM(b.sqm) * 100, 1) END                                              AS sqm_pct_done,
            COALESCE(SUM(b.sqm) FILTER (WHERE b.status_sequence >= 700), 0)                       AS sqm_printed,
            CASE WHEN COALESCE(SUM(b.sqm), 0) = 0 THEN 0
                 ELSE ROUND(COALESCE(SUM(b.sqm) FILTER (WHERE b.status_sequence >= 700), 0)
                          / SUM(b.sqm) * 100, 1) END                                              AS sqm_pct_printed,
            COALESCE(SUM(b.sqm) FILTER (WHERE b.status_sequence >= 801), 0)                       AS sqm_cut,
            CASE WHEN COALESCE(SUM(b.sqm), 0) = 0 THEN 0
                 ELSE ROUND(COALESCE(SUM(b.sqm) FILTER (WHERE b.status_sequence >= 801), 0)
                          / SUM(b.sqm) * 100, 1) END                                              AS sqm_pct_cut
        FROM bucketed b
        GROUP BY b.content, b.nav, b.bucket_index, b.bucket_date, b.effective_line
    )
    SELECT
        a.content,
        a.nav,
        a.bucket_index,
        a.bucket_date,
        a.production_line,
        a.order_count,
        a.order_open,
        a.order_done,
        a.order_pct_done,
        a.order_printed,
        a.order_pct_printed,
        a.order_cut,
        a.order_pct_cut,
        a.customer_count,
        a.sqm_total,
        a.sqm_open,
        a.sqm_done,
        a.sqm_pct_done,
        a.sqm_printed,
        a.sqm_pct_printed,
        a.sqm_cut,
        a.sqm_pct_cut,
        EXTRACT(EPOCH FROM CURRENT_TIME)::numeric                      AS current_time_epoch,
        (ev.result ->>'sqm_color_index')::numeric                      AS sqm_color_index,
        (ev.result ->>'order_color_index')::numeric                    AS order_color_index
    FROM aggregated a
    CROSS JOIN LATERAL (
        SELECT public.evaluate_many_nas(
            v_buckets->a.bucket_index->'formula',
            COALESCE(v_buckets->a.bucket_index->'params', '{}'::jsonb)
            || jsonb_build_object(
                'current_time_epoch', EXTRACT(EPOCH FROM CURRENT_TIME)::numeric,
                'sqm_pct_done',       a.sqm_pct_done,
                'order_pct_done',     a.order_pct_done
            )
        ) AS result
    ) ev
    ORDER BY a.production_line, a.bucket_date NULLS FIRST;
END;
$$;

alter function mapping.get_sitrep(text, text[], integer) owner to xfw3;

