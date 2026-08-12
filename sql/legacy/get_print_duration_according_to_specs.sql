create function get_print_duration_according_to_specs(p_resource_uid text, p_nest_name text) returns numeric
	stable
	parallel safe
	language sql
as $$
  with rc as (
    select
      ld.resource_uid,
      n.width,
      n.height,
      s.print_mode,
      s.print_passes,
      case when s.passoverlap_level = 'Flat50' then 3
           else substring(s.passoverlap_level from 2 for length(s.passoverlap_level) - 1)::int
      end as passoverlap_level,
      s.horizontal_resolution,
      s.vertical_resolution
    from log.data ld
    join legacy.nest n on n.nest_name = ld.nest_name
    cross join lateral jsonb_to_record(ld.data_json::jsonb -> 'process_steps' -> 0) as s(
      print_mode text,
      print_passes integer,
      passoverlap_level text,
      horizontal_resolution integer,
      vertical_resolution integer
    )
    where ld.resource_uid = p_resource_uid and ld.nest_name = p_nest_name and ld.amount > 0
      and ld.step = 'print'
    limit 1
  )
  select evaluate_formula(
           jsonb_build_object('nodes', eq.nodes, 'connections', eq.connections),
           jsonb_build_object(
             'print_speed_sqm', (eqm.params ->> 'print_speed_sqm')::int,
             'media_width',     (eqm.params ->> 'media_width')::int,
             'width',  case when rc.height > rc.width and rc.height <= (eqm.params ->> 'media_width')::int
                            then greatest(rc.width, rc.height) else rc.width end,
             'height', case when rc.height > rc.width and rc.height <= (eqm.params ->> 'media_width')::int
                            then least(rc.width, rc.height) else rc.height end
           )
         )::numeric
  from rc
  join relation.resource r on r.resource_uid = rc.resource_uid
  join relation.equipment e on e.equipment_id = (r.resource_json::jsonb ->> 'equipment_id')::int
  cross join lateral jsonb_to_record(e.equipment_json::jsonb -> 'data') as eq(nodes jsonb, connections jsonb, modi jsonb)
  cross join lateral jsonb_array_elements(eq.modi) as modi(val)
  cross join lateral jsonb_to_record(modi.val) as eqm(
    print_mode text,
    print_passes integer,
    horizontal_resolution integer,
    vertical_resolution integer,
    passoverlap_level integer,
    params jsonb
  )
  where eqm.print_mode            = rc.print_mode
    and eqm.print_passes          = rc.print_passes
    and (eqm.passoverlap_level     = rc.passoverlap_level OR rc.passoverlap_level IS NULL)
    and eqm.horizontal_resolution = rc.horizontal_resolution
    and eqm.vertical_resolution   = rc.vertical_resolution
  limit 1;
$$;

alter function get_print_duration_according_to_specs(text, text) owner to xfw3;

