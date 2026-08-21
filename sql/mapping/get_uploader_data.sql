create function mapping.get_uploader_data(p_production_orderline_id integer) returns TABLE(uploader_data_id integer, production_orderline_id integer, order_id integer, sales_orderline_id integer, status text, amount integer, front_file_name text, front_preview_url text, front_width numeric, front_height numeric, back_file_name text, back_preview_url text, back_width numeric, back_height numeric)
	stable
	language plpgsql
as $$
declare
    v_bucket_url text := 'http://s3-eu-west-1.amazonaws.com/proboprodbucket/';
begin
    return query
    select
        ud.uploader_data_id,
        cs.production_orderline_id,
        cs.order_id,
        cs.sales_orderline_id,
        ud.line_json->'data'->>'status',
        (p->>'amount')::integer,
        p->'front_side'->'file'->>'file_name',
        v_bucket_url || (p->'front_side'->'file'->>'preview_url'),
        (p->'front_side'->'file'->>'width')::numeric,
        (p->'front_side'->'file'->>'height')::numeric,
        p->'back_side'->'file'->>'file_name',
        v_bucket_url || (p->'back_side'->'file'->>'preview_url'),
        (p->'back_side'->'file'->>'width')::numeric,
        (p->'back_side'->'file'->>'height')::numeric
    from mapping.component_specs cs
    join mapping.uploader_data ud on ud.uploader_data_id = cs.uploader_data_id,
         jsonb_array_elements(ud.line_json->'data'->'products') as p
    where cs.production_orderline_id = p_production_orderline_id;
end;
$$;

alter function mapping.get_uploader_data(integer) owner to xfw3;

