create function log.crud_error_log(p_param_json jsonb, p_no_results boolean DEFAULT false) returns TABLE(track_by integer, crud text, error_log_id bigint, resource_uid text, start_at timestamp with time zone, end_at timestamp with time zone, code text, severity text, message text, context_json jsonb, source text, source_ref text, source_ts timestamp with time zone, page_number integer)
	language plpgsql
as $$
#variable_conflict use_column
declare
  rec jsonb;
  v_data jsonb;
  v_resource text;
  v_message text;
  v_start_at timestamp with time zone;
  v_day_start timestamp with time zone;
  v_day_end timestamp with time zone;
  v_exists boolean;
begin

  for rec in
    select value
    from jsonb_array_elements(p_param_json) as e(value)
    where e.value ->> 'crud' = 'create'
    order by e.value -> 'data' ->> 'resource_uid',
             (e.value -> 'data' ->> 'start_at')::timestamptz,
             (e.value ->> 'track_by')::integer
  loop

    v_data := rec -> 'data';
    v_resource := v_data ->> 'resource_uid';
    v_message := v_data ->> 'message';
    v_start_at := (v_data ->> 'start_at')::timestamptz;

    -- lokale dag-grenzen, DST-correct: lokale wandklok, dag afkappen, +1 dag, terug naar timestamptz
    v_day_start := date_trunc('day', v_start_at at time zone 'Europe/Amsterdam') at time zone 'Europe/Amsterdam';
    v_day_end   := (date_trunc('day', v_start_at at time zone 'Europe/Amsterdam') + interval '1 day') at time zone 'Europe/Amsterdam';

    -- staat dezelfde message die dag al voor deze resource? (zelfde transactie telt mee)
    select exists (
      select 1
      from log.error er
      where er.resource_uid = v_resource
        and er.message is not distinct from v_message
        and er.start_at >= v_day_start
        and er.start_at <  v_day_end
    ) into v_exists;

    if not v_exists then
      return query
      insert into log.error as er (
        resource_uid, start_at, end_at, code, severity, message,
        context_json, source, source_ref, source_ts, page_number
      )
      values (
        v_resource,
        v_start_at,
        (v_data ->> 'end_at')::timestamptz,
        v_data ->> 'code',
        v_data ->> 'severity',
        v_message,
        coalesce(v_data -> 'context_json', '{}'::jsonb),
        v_data ->> 'source',
        v_data ->> 'source_ref',
        (v_data ->> 'source_ts')::timestamptz,
        (rec ->> 'page_number')::integer
      )
      on conflict on constraint uq_error_log do nothing
      returning
        (rec ->> 'track_by')::integer,
        rec ->> 'crud',
        er.error_log_id,
        er.resource_uid,
        er.start_at,
        er.end_at,
        er.code,
        er.severity,
        er.message,
        er.context_json,
        er.source,
        er.source_ref,
        er.source_ts,
        (rec ->> 'page_number')::integer;
    end if;

  end loop;

  if p_no_results then return; end if;

end;
$$;

alter function log.crud_error_log(jsonb, boolean) owner to xfw3;

