create or replace function mock.get_material_planning_aggregate(p_production_line_id integer) returns TABLE(material_id integer, ready_to_nest_count bigint, ready_to_nest_product_amount numeric, ready_to_nest_sqm numeric, needs_dtp_count bigint, needs_dtp_product_amount numeric, needs_dtp_sqm numeric, rework_lines_count bigint, rework_amount numeric, rework_sqm numeric, class_name text[])
	stable
	language plpgsql
as $$
#variable_conflict use_column
declare
    -- below this sequence an orderline still needs dtp; up to v_nested_until it
    -- is ready to nest
    v_nested_sequence constant integer := 450;
    v_nested_until    constant integer := 495;
begin
    return query
    -- The open orderlines of the line, whatever their date, from the same
    -- detail every other board reads (mock.get_production_orderline_details
    -- is gone). Rework = own rework or a rerun of one of its nests.
    with d as (
        select x.material_id, x.status_sequence, x.product_amount, x.sqm, x.class_names,
               (x.impact_json ->> 'rework_count')::integer  > 0     as has_rework,
               (x.impact_json ->> 'rework_amount')::numeric         as rework_amount,
               (x.impact_json ->> 'rework_sqm')::numeric            as rework_sqm
        from mapping.get_production_orderline_detail(
                 p_production_line_id => p_production_line_id,
                 p_is_open            => true) x
    )
    select
        d.material_id,
        count(*)              filter (where d.status_sequence between v_nested_sequence and v_nested_until and not d.has_rework) as ready_to_nest_count,
        sum(d.product_amount) filter (where d.status_sequence between v_nested_sequence and v_nested_until and not d.has_rework) as ready_to_nest_product_amount,
        sum(d.sqm)            filter (where d.status_sequence between v_nested_sequence and v_nested_until and not d.has_rework) as ready_to_nest_sqm,
        count(*)              filter (where d.status_sequence < v_nested_sequence and not d.has_rework) as needs_dtp_count,
        sum(d.product_amount) filter (where d.status_sequence < v_nested_sequence and not d.has_rework) as needs_dtp_product_amount,
        sum(d.sqm)            filter (where d.status_sequence < v_nested_sequence and not d.has_rework) as needs_dtp_sqm,
        count(*)              filter (where d.has_rework)                                               as rework_lines_count,
        sum(d.rework_amount)  filter (where d.has_rework)                                               as rework_amount,
        sum(d.rework_sqm)     filter (where d.has_rework)                                               as rework_sqm,
        -- every class name of the material once; unnest per row first, an
        -- array_agg over the array column trips over empty arrays
        array_remove(array_agg(distinct cn.value), null)                                                as class_name
    from d
    left join lateral unnest(d.class_names) as cn(value) on true
    group by d.material_id
    order by d.material_id;
end;
$$;

alter function mock.get_material_planning_aggregate(integer) owner to xfw3;
