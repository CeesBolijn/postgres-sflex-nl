create function mapping.get_time_on_status(p_model text DEFAULT NULL::text, p_from timestamp with time zone DEFAULT now(), p_days integer DEFAULT 5, p_production_line_id integer DEFAULT NULL::integer) returns TABLE(logistics_date date, production_order_id integer, order_id integer, production_order text, material_name text, status_name text, sqm numeric, time_on_status_hours numeric, color text, count_warning bigint, color_warning text, count_critical bigint, color_critical text, production_line_id integer, production_line_name text)
	stable
	language plpgsql
as $$
DECLARE
  v_from date;
  v_until date;
BEGIN
  v_from := date_trunc('day', p_from)::date;

  SELECT d.date + 1 INTO v_until
  FROM action.dates d
  WHERE d.date >= v_from
    AND NOT d.is_weekend
    AND NOT COALESCE(d.is_mandatory_day_off, false)
  ORDER BY d.date
  OFFSET p_days - 1
  LIMIT 1;

  RETURN QUERY
  WITH color_lookup AS (
      SELECT
          grp ->> 'code' AS code,
          (grp ->> 'min_value')::numeric AS min_value,
          (grp ->> 'max_value')::numeric AS max_value,
          grp ->> 'color' AS color
      FROM legacy.lookup rl,
           jsonb_array_elements(rl.lookup_json) AS grp
      WHERE rl.lookup = 'lookup_time_on_status'
  ),
  base AS (
      SELECT
          v.logistics_date::date AS logistics_date,
          v.production_order_id,
          v.order_id,
          v.production_order,
          v.material_name,
          v.status_name,
          v.first_production_line_id,
          pl.line AS production_line_name,
          SUM(v.sqm) AS sqm,
          MAX(v.time_on_status_hours) AS time_on_status_hours
      FROM mapping.v_production_orderlines v
      JOIN relation.production_line pl ON pl.line_id = v.first_production_line_id
      WHERE v.is_open = true
        AND v.logistics_date >= v_from
        AND v.logistics_date < v_until
        AND (p_model IS NULL OR v.effective_model = p_model)
        AND (p_production_line_id IS NULL OR v.first_production_line_id = p_production_line_id)
      GROUP BY
          v.logistics_date::date,
          v.production_order_id,
          v.order_id,
          v.production_order,
          v.material_name,
          v.status_name,
          v.first_production_line_id,
          pl.line
  ),
  colored AS (
      SELECT
          b.*,
          cl.code AS color_code,
          cl.color
      FROM base b
      LEFT JOIN color_lookup cl
          ON b.time_on_status_hours >= cl.min_value
         AND (cl.max_value IS NULL OR b.time_on_status_hours < cl.max_value)
  ),
  counts AS (
    SELECT
        c.logistics_date,
        SUM(CASE WHEN c.color_code = 'warning' THEN 1 ELSE 0 END) AS count_warning,
        MAX(CASE WHEN c.color_code = 'warning' THEN c.color END) AS color_warning,
        SUM(CASE WHEN c.color_code = 'critical' THEN 1 ELSE 0 END) AS count_critical,
        MAX(CASE WHEN c.color_code = 'critical' THEN c.color END) AS color_critical
    FROM colored c
    GROUP BY c.logistics_date
  )
  SELECT
      c.logistics_date,
      c.production_order_id,
      c.order_id,
      c.production_order,
      c.material_name,
      c.status_name,
      c.sqm,
      c.time_on_status_hours,
      c.color,
      cnt.count_warning,
      cnt.color_warning,
      cnt.count_critical,
      cnt.color_critical,
      c.first_production_line_id,
      c.production_line_name
  FROM colored c
  JOIN counts cnt ON cnt.logistics_date = c.logistics_date
  ORDER BY c.logistics_date, c.time_on_status_hours DESC;
END;
$$;

alter function mapping.get_time_on_status(text, timestamp with time zone, integer, integer) owner to xfw3;

