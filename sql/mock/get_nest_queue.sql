create function get_nest_queue(p_material_id integer) returns TABLE(queue_name text, production_location text, nest_bucket_id integer, bucket_width numeric, bucket_min_height numeric, bucket_max_height numeric, nest_job_id integer, resource_json jsonb, job_name text, job_amount integer, waste_perc numeric, deadline_fill_perc numeric, deadline_at timestamp with time zone, remarks_json jsonb, production_orderline_id integer, nest_id integer, document_amount numeric, document_width numeric, document_height numeric)
	stable
	language plpgsql
as $$
#variable_conflict use_column
BEGIN
    RETURN QUERY
    SELECT
        nq.name,
        nb.production_location,
        nb.nest_bucket_id,
        nb.width bucket_width,
        nb.min_height bucket_min_height,
        nb.max_height bucket_max_height,
        nj.nest_job_id,
        nj.resource_json,
        nj.job_name,
        nj.amount,
        nj.waste_perc,
        nj.deadline_fill_perc,
        nj.deadline_at,
        nj.remarks_json,
        nd.production_orderline_id,
        nj.mock_nest_id,
        nd.amount,
        nd.width,
        nd.height
    FROM mock.nest_queue nq
    JOIN mock.nest_bucket nb ON nq.nest_queue_id = nb.nest_queue_id
    JOIN mock.nest_job nj ON nb.nest_bucket_id = nj.nest_bucket_id
    JOIN mock.nest_document nd ON nj.nest_job_id = nd.nest_job_id
    WHERE nq.material_ids @> ARRAY[p_material_id]
    ORDER BY deadline_at;
END;
$$;

alter function get_nest_queue(integer) owner to xfw3;

