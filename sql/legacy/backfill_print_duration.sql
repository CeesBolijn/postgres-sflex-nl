create procedure backfill_print_duration(IN p_batch_size integer DEFAULT 5000, IN p_start_id bigint DEFAULT 0)
	language plpgsql
as $$
declare
  v_max  bigint;
  v_from bigint;
  v_to   bigint;
  v_upd  bigint;
  v_miss bigint;
begin
  select max(data_log_id) into v_max
  from log.data where step = 'print';

  v_from := p_start_id;
  while v_from <= v_max loop
    v_to := v_from + p_batch_size - 1;

    with computed as (
      select
        d.data_log_id,
        d.resource_uid,
        d.nest_name,
        d.production_time_seconds as old_seconds,
        legacy.get_print_duration_according_to_specs(d.resource_uid, d.nest_name)::integer as new_seconds
      from log.data d  JOIN relation.resource r
        ON d.resource_uid = r.resource_uid
      where d.step = 'print'
        and d.amount > 0
        and d.nest_name is not null
        and r.line_id <> 9
        and d.data_log_id between v_from and v_to
    ),
    updated as (
      update log.data d
      set production_time_seconds = c.new_seconds
      from computed c
      where d.data_log_id = c.data_log_id
        and c.new_seconds is not null
        and c.new_seconds is distinct from d.production_time_seconds
      returning 1
    ),
    logged as (
      insert into log.data_duration_check as chk
        (data_log_id, resource_uid, nest_name, old_seconds, checked_at)
      select c.data_log_id, c.resource_uid, c.nest_name, c.old_seconds, now()
      from computed c
      where c.new_seconds is null
      on conflict on constraint data_duration_check_data_log_id_key do update set
        old_seconds = excluded.old_seconds,
        checked_at  = excluded.checked_at
      returning 1
    )
    select (select count(*) from updated), (select count(*) from logged)
    into v_upd, v_miss;

    commit;

    raise notice 'ids % .. % : updated %, missing %', v_from, v_to, v_upd, v_miss;

    v_from := v_to + 1;
  end loop;
end;
$$;

alter procedure backfill_print_duration(integer, bigint) owner to xfw3;

