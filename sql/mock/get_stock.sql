create function get_stock(p_material_id integer, p_bucket_width numeric DEFAULT NULL::numeric) returns TABLE(spec_id bigint, vendor_batch_id text, amount integer, width numeric)
	stable
	language plpgsql
as $$
#variable_conflict use_column
declare
    v_stock_sequence integer := (select sequence
                                 from   job.status
                                 where  code = 'stock');
begin
    return query
        select s.spec_id,
               s.spec_json ->> 'vendor_batch_id',
               ( coalesce(sum(sl.amount) filter (where sl.to_status_sequence   = v_stock_sequence), 0)
               - coalesce(sum(sl.amount) filter (where sl.from_status_sequence = v_stock_sequence), 0)
               )::integer,
               (s.spec_json ->> 'width')::numeric
        from   mock.spec s
        join   mock.spec_log sl on sl.spec_id = s.spec_id
        where  (s.spec_json ->> 'material_id')::integer = p_material_id
        and    (p_bucket_width is null or (s.spec_json ->> 'width')::numeric <= p_bucket_width)
        group  by s.spec_id,
                  s.spec_json ->> 'vendor_batch_id',
                  (s.spec_json ->> 'width')::numeric
        having ( coalesce(sum(sl.amount) filter (where sl.to_status_sequence   = v_stock_sequence), 0)
               - coalesce(sum(sl.amount) filter (where sl.from_status_sequence = v_stock_sequence), 0)
               ) > 0
        order  by 4, 3;
end;
$$;

alter function get_stock(integer, numeric) owner to xfw3;

