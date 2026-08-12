create function crud_hr_shift_planning_log(p_param_json jsonb, p_no_results boolean DEFAULT false) returns TABLE(track_by integer, crud text, shift_planning_id integer, department_group_id integer, business_date date, shift_json jsonb, updated_at timestamp with time zone)
	language plpgsql
as $$
#variable_conflict use_column
declare
  rec jsonb;
  v_data jsonb;
begin

  for rec in
    select value from jsonb_array_elements(p_param_json) as e(value)
  loop

    v_data := rec -> 'data';

    return query
    insert into log.hr_shift_planning as s (
      department_group_id, business_date, shift_json
    )
    values (
      (v_data ->> 'department_group_id')::int,
      (v_data ->> 'business_date')::date,
      coalesce(v_data -> 'shift_json', '{}'::jsonb)
    )
    on conflict (department_group_id, business_date) do update set
      shift_json = excluded.shift_json,
      updated_at = now()
    returning
      (rec ->> 'track_by')::integer,
      rec ->> 'crud',
      s.shift_planning_id,
      s.department_group_id,
      s.business_date,
      s.shift_json,
      s.updated_at;

  end loop;

  if p_no_results then return; end if;

end;
$$;

alter function crud_hr_shift_planning_log(jsonb, boolean) owner to xfw3;

