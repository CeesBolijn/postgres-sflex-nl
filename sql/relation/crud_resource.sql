create function crud_resource(p_param_json jsonb, p_no_results boolean DEFAULT false) returns TABLE(track_by integer, crud text, resource_uid text, resource_json jsonb)
	language plpgsql
as $$
#variable_conflict use_column
begin

  return query
  with src as (
    select distinct on (el.val -> 'data' ->> 'resource_uid')
      (el.val ->> 'track_by')::integer as track_by,
      el.val ->> 'crud' as crud,
      el.val -> 'data' ->> 'resource_uid' as resource_uid,
      el.val -> 'data' -> 'resource_json' as resource_json
    from jsonb_array_elements(p_param_json) with ordinality as el(val, ord)
    where el.val ->> 'crud' = 'merge'
    order by el.val -> 'data' ->> 'resource_uid', el.ord desc
  ),
  ins as (
    insert into relation.resource as r (resource_uid, resource_json)
    select src.resource_uid, src.resource_json from src
    on conflict (resource_uid) do update set
      resource_json = r.resource_json || excluded.resource_json
    returning r.resource_uid, r.resource_json
  )
  select s.track_by, s.crud, ins.resource_uid, ins.resource_json
  from ins
  join src s on s.resource_uid = ins.resource_uid;

  if p_no_results then return; end if;

end;
$$;

alter function crud_resource(jsonb, boolean) owner to xfw3;

