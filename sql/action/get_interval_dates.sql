create function action.get_interval_dates(p_reference_date date, p_current_date date, p_interval integer, p_look_ahead_days integer, p_include_weekends boolean DEFAULT false, p_include_mandatory_days_off boolean DEFAULT true, p_day_offset integer DEFAULT 0) returns TABLE(interval_date date)
	stable
	language sql
as $$
    WITH sequenced AS (       -- alle werkdagen, doorlopend genummerd
        SELECT
            d.date,
            ROW_NUMBER() OVER (ORDER BY d.date) AS seq
        FROM action.dates d
        WHERE (p_include_weekends OR d.is_weekend = FALSE)
          AND (p_include_mandatory_days_off OR d.is_mandatory_day_off IS NOT TRUE)
    ),
    shifted AS (               -- reference en current verschoven volgens de formule
        SELECT
            (SELECT seq FROM sequenced WHERE date = p_reference_date)
                + p_day_offset
                + ((SELECT seq FROM sequenced WHERE date = p_current_date)
                   - (SELECT seq FROM sequenced WHERE date = p_reference_date))
                  * sign(p_day_offset)::integer AS reference_seq,
            (SELECT seq FROM sequenced WHERE date = p_current_date) + p_day_offset AS current_seq
    )
    SELECT s.date AS interval_date
    FROM sequenced s, shifted a
    WHERE s.seq >= a.current_seq
      AND (s.seq - a.reference_seq) % p_interval = 0   -- valt op het interval
      AND s.seq - a.current_seq < p_look_ahead_days     -- binnen de komende N werkdagen
    ORDER BY s.date;
$$;

alter function action.get_interval_dates(date, date, integer, integer, boolean, boolean, integer) owner to xfw3;

