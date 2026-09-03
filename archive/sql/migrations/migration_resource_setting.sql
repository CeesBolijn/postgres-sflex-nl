-- production.resource_setting: how fast a resource is, per imposition group
-- (= per material while the alias holds). The setting hangs on a
-- resource_path so it can cover a branch or one machine.
--
-- What belongs here and what does not:
--   * how many impositions a job needs follows from the FORMAT and the waste
--     of the material — the same job on a 210 or a 320 needs the same number
--     of sheets. That lives in catalog.imposition_group.imposition_group_json.
--   * how long one square metre takes is the MACHINE. That is here.
--
-- Measured over 60 days from log.data.production_time_seconds joined to
-- legacy.nest on nest_name. Medians, not averages: the averages are wrecked
-- by outliers (one 350 m2 "sheet" pushed bh.sheet.impose.320 from 27 to 104
-- seconds per m2, which made the wider machine look slower than the narrow
-- one). On medians the 320s are faster than the 210s, as they should be.

BEGIN;

CREATE TABLE IF NOT EXISTS production.resource_setting
(
    resource_setting_id bigint generated always as identity primary key,
    resource_path       ltree not null,
    imposition_group_id integer,
    setting_json        jsonb default '{}'::jsonb not null,
    moved_at            timestamp with time zone default now() not null
);

COMMENT ON TABLE production.resource_setting IS
    'Speed settings per resource branch and imposition group. setting_json holds the formula array plus its constants; append-only, newest moved_at wins.';

ALTER TABLE production.resource_setting OWNER TO xfw3;

CREATE INDEX IF NOT EXISTS ix_resource_setting_lookup
    ON production.resource_setting (resource_path, imposition_group_id, moved_at desc);
CREATE INDEX IF NOT EXISTS ix_resource_setting_path_gist
    ON production.resource_setting USING gist (resource_path);

WITH measured AS (
    SELECT subpath(r.resource_path, 0, 2)::text || '.impose.' ||
           subpath(r.resource_path, 3, 1)::text AS impose_path,
           percentile_cont(0.5) WITHIN GROUP (
               ORDER BY d.production_time_seconds
                        / nullif((n.nest_json ->> 'material_width')::numeric
                                 * (n.nest_json ->> 'material_height')::numeric / 10000.0, 0)
           ) AS seconds_per_sqm,
           count(*) AS nests
    FROM log.data d
    JOIN legacy.nest n       ON n.nest_name = d.nest_name   -- nest_id is never filled
    JOIN relation.resource r ON r.resource_uid = d.resource_uid
    WHERE d.start_at > now() - interval '60 days'
      AND d.step = 'print'
      AND d.production_time_seconds BETWEEN 1 AND 36000
      AND n.nest_json ? 'material_width'
      AND (n.nest_json ->> 'material_width')::numeric > 0
      AND (n.nest_json ->> 'material_height')::numeric > 0
      AND r.resource_path ~ '*.print.*'
      AND nlevel(r.resource_path) >= 4
    GROUP BY 1
    HAVING count(*) > 200
)
INSERT INTO production.resource_setting (resource_path, imposition_group_id, setting_json)
SELECT i.resource_path,
       NULL,   -- baseline: applies to every group until one gets its own row
       jsonb_build_object(
           'formula', jsonb_build_array(
               'gross_sqm=net_sqm*(1+waste_factor)',
               'impositions=ceil(gross_sqm/imposition_sqm)',
               'duration_in_seconds=gross_sqm*seconds_per_sqm*cut_factor+setup_seconds'),
           'seconds_per_sqm',     round(m.seconds_per_sqm::numeric, 1),
           'cut_factor',          1,
           'setup_seconds',       0,
           'measured_over_nests', m.nests)
FROM relation.resource i
JOIN measured m ON m.impose_path = i.resource_path::text
WHERE i.resource_path ~ '*.impose.*';
-- No "skip if it exists" guard: the table is append-only and the newest
-- moved_at wins, so re-running simply lays a fresh measurement over the old
-- one. That is also how you refresh the baseline later.

COMMIT;

-- imposition_sqm is deliberately absent here: it is a property of the format,
-- and arrives as a variable from the group. Tune from here — a group that cuts
-- slower gets its own row with a cut_factor, a machine that differs gets a row
-- on its own deeper path; both win because the lookup takes the longest path
-- and prefers a named group.
