create materialized view v_resource_capacity as
	WITH batch_data AS (
         SELECT b.batch_uid,
            b.batch_at::date AS batch_date,
            r_1.resource_uid,
            r_1.line_id AS production_line_id,
            GREATEST(trunc((b.batch_json ->> 'width'::text)::numeric)::integer, trunc((b.batch_json ->> 'height'::text)::numeric)::integer) AS width,
            LEAST(trunc((b.batch_json ->> 'width'::text)::numeric)::integer, trunc((b.batch_json ->> 'height'::text)::numeric)::integer) AS height,
            (b.batch_json ->> 'material_id'::text)::integer AS material_id,
            COALESCE((((mpl.line_json -> 'specs'::text) -> 0) ->> 'sides'::text)::integer, 1) AS sides,
            mpl.line_json ->> 'name'::text AS material_name
           FROM legacy.batch b
             JOIN relation.resource r_1 ON ((b.batch_json ->> 'print_production_unit_id'::text)::integer) = ((r_1.resource_json ->> 'pv2_id'::text)::integer)
             LEFT JOIN mapping.material_production_line mpl ON mpl.material_id = ((b.batch_json ->> 'material_id'::text)::integer) AND mpl.production_line_id = r_1.line_id
          WHERE b.batch_at > (now() - '3 mons'::interval)
        ), amounts AS (
         SELECT bd.batch_date,
            bd.resource_uid,
            bd.production_line_id,
            bd.width,
            bd.height,
            bd.sides,
            bd.material_id,
            bd.material_name,
            sum((n.nest_json ->> 'nest_amount'::text)::integer) AS amount
           FROM batch_data bd
             JOIN legacy.nest n ON bd.batch_uid = n.batch_uid
          GROUP BY bd.batch_date, bd.resource_uid, bd.production_line_id, bd.width, bd.height, bd.sides, bd.material_id, bd.material_name
        ), with_profile AS (
         SELECT a.batch_date,
            a.resource_uid,
            a.production_line_id,
            a.width,
            a.height,
            a.sides,
            a.material_id,
            a.material_name,
            a.amount,
            rip.profile_name,
            evaluate_many_nas(f.formula_json, (p.profile_json -> 'params'::text) || jsonb_build_object('width', a.width, 'height', a.height, 'sides', a.sides)) AS data_json
           FROM amounts a
             JOIN relation.resource_item_profile rip ON rip.resource_uid = a.resource_uid AND (a.material_id = ANY (rip.material_ids)) AND ('production'::text = ANY (rip.profile_state))
             JOIN relation.profile p ON p.domain_id = rip.domain_id AND p.profile_name = rip.profile_name AND p.active = true
             LEFT JOIN relation.formula f ON f.formula_id = p.formula_id
        )
 SELECT wp.batch_date,
    wp.resource_uid,
    r.resource_json ->> 'name'::text AS resource_name,
    wp.profile_name,
    wp.width,
    wp.height,
    wp.sides,
    wp.material_id,
    COALESCE(wp.material_name, 'Unknown'::text) AS material_name,
    wp.amount,
    round(wp.amount::numeric / sum(wp.amount) OVER (PARTITION BY wp.batch_date, wp.resource_uid), 4) AS weight,
    wp.data_json,
    rank() OVER (PARTITION BY wp.batch_date, wp.resource_uid, wp.width, wp.height, wp.sides, wp.material_id ORDER BY ((wp.data_json ->> 'panels_hour'::text)::numeric) DESC) = 1 AS is_fastest_profile
   FROM with_profile wp
     JOIN relation.resource r ON r.resource_uid = wp.resource_uid
  ORDER BY wp.batch_date, wp.resource_uid, wp.amount DESC;

alter materialized view v_resource_capacity owner to xfw3;

create unique index resource_capacity_idx
	on v_resource_capacity (batch_date, resource_uid, width, height, sides, material_id, profile_name);

