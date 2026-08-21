create function job.spec_unit_status_update_batch(p_nest_id bigint, p_current_status_sequence integer, p_new_status_sequence integer, p_updates jsonb DEFAULT NULL::jsonb, p_resource_uids text[] DEFAULT NULL::text[]) returns void
	language plpgsql
as $$
DECLARE
    v_specs JSONB;
BEGIN
    -- Bulk mode reads per-spec amounts from the nest placement; update mode takes them explicitly.
    IF p_updates IS NULL OR jsonb_array_length(p_updates) = 0 THEN
        IF p_nest_id IS NULL THEN
            RAISE EXCEPTION 'p_updates is required when p_nest_id is NULL';
        END IF;
        SELECT placement_json -> 'specs' INTO v_specs
          FROM production.nest WHERE nest_id = p_nest_id;
    ELSE
        v_specs := p_updates;
    END IF;

    INSERT INTO job.spec_event (spec_id, from_status_sequence, to_status_sequence, amount, remaining_impact_delta, resource_uids)
    SELECT el.spec_id,
           p_current_status_sequence,
           p_new_status_sequence,
           jsonb_array_length(el.placement),
           jsonb_array_length(el.placement) * (
               COALESCE(SUM(m.production_impact_per_unit) FILTER (WHERE (m.possible_status_sequence #>> '{0,0}')::INTEGER >= p_new_status_sequence), 0)
             - COALESCE(SUM(m.production_impact_per_unit) FILTER (WHERE (m.possible_status_sequence #>> '{0,0}')::INTEGER >= p_current_status_sequence), 0)
           )::INTEGER,
           COALESCE(p_resource_uids, '{}')
      FROM jsonb_to_recordset(COALESCE(v_specs, '[]'::jsonb)) AS el(spec_id BIGINT, placement JSONB)
      LEFT JOIN job.spec_unit_manifest m ON m.spec_id = el.spec_id
     GROUP BY el.spec_id, el.placement;
END;
$$;

alter function job.spec_unit_status_update_batch(bigint, integer, integer, jsonb, text[]) owner to xfw3;

