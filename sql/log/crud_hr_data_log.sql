create function log.crud_hr_data_log(p_param_json jsonb, p_no_results boolean DEFAULT false) returns TABLE(track_by integer, crud text, hr_data_log_id integer, employee_id integer, department_id integer, department_group_id integer, business_date date, shift text, start_at timestamp with time zone, end_at timestamp with time zone, source text, source_ref text, ingested_at timestamp with time zone, updated_at timestamp with time zone)
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
    insert into log.hr_data as h (
      employee_id, department_id, department_group_id,
      business_date, shift,
      start_at, end_at,
      source, source_ref
    )
    values (
      (v_data ->> 'employee_id')::int,
      (v_data ->> 'department_id')::int,
      (v_data ->> 'department_group_id')::int,
      (v_data ->> 'business_date')::date,
      v_data ->> 'shift',
      (v_data ->> 'start_at')::timestamptz,
      (v_data ->> 'end_at')::timestamptz,
      coalesce(v_data ->> 'source', 'dyflexis'),
      v_data ->> 'source_ref'
    )
--     on conflict (employee_id, business_date, shift) do update set
--       department_id = excluded.department_id,
--       department_group_id = excluded.department_group_id,
--       start_at = excluded.start_at,
--       end_at = coalesce(excluded.end_at, h.end_at),
--       source = excluded.source,
--       source_ref = coalesce(excluded.source_ref, h.source_ref),
--       updated_at = now()
    on conflict (employee_id, business_date, shift) do update set
      department_id       = coalesce(excluded.department_id,       h.department_id),
      department_group_id = coalesce(excluded.department_group_id, h.department_group_id),
      start_at            = coalesce(excluded.start_at,            h.start_at),
      end_at              = coalesce(excluded.end_at,              h.end_at),
      source              = excluded.source,
      source_ref          = coalesce(excluded.source_ref,          h.source_ref),
      updated_at          = now()  
    returning
      (rec ->> 'track_by')::integer,
      rec ->> 'crud',
      h.hr_data_log_id,
      h.employee_id,
      h.department_id,
      h.department_group_id,
      h.business_date,
      h.shift,
      h.start_at,
      h.end_at,
      h.source,
      h.source_ref,
      h.ingested_at,
      h.updated_at;

  end loop;

  if p_no_results then return; end if;

end;
$$;

alter function log.crud_hr_data_log(jsonb, boolean) owner to xfw3;

