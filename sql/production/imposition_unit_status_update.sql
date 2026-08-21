create function production.imposition_unit_status_update(p_imposition_id bigint, p_current_status_sequence integer, p_new_status_sequence integer, p_resource_uids text[] DEFAULT NULL::text[]) returns void
	language plpgsql
as $$
DECLARE
    v_amount INTEGER;
BEGIN
    -- Run quantity of the imposition = qty of the imposition-level movement.
    SELECT amount INTO v_amount FROM production.imposition WHERE imposition_id = p_imposition_id;

    IF v_amount IS NULL THEN
        RAISE EXCEPTION 'imposition not found: imposition_id=%', p_imposition_id;
    END IF;

    -- Imposition-level movement: one append-only row.
    -- remaining_impact_delta = qty * ( R(to) - R(from) ), R(S) from the frozen imposition manifest.
    INSERT INTO production.imposition_event (
        imposition_id, from_status_sequence, to_status_sequence,
        amount, remaining_impact_delta, resource_uids
    )
    SELECT p_imposition_id,
           p_current_status_sequence,
           p_new_status_sequence,
           v_amount,
           v_amount * (
               COALESCE(SUM(production_impact_per_unit)
                        FILTER (WHERE (possible_status_sequence #>> '{0,0}')::INTEGER >= p_new_status_sequence), 0)
             - COALESCE(SUM(production_impact_per_unit)
                        FILTER (WHERE (possible_status_sequence #>> '{0,0}')::INTEGER >= p_current_status_sequence), 0)
           )::INTEGER,
           COALESCE(p_resource_uids, '{}')
      FROM production.imposition_unit_manifest
     WHERE imposition_id = p_imposition_id;

    -- Cascade to all specs on the imposition (bulk mode reads placement_json.specs).
    -- Same resources flow through: the printer that ran the imposition ran its specs.
    PERFORM job.spec_unit_status_update_batch(
        p_imposition_id, p_current_status_sequence, p_new_status_sequence, NULL, p_resource_uids
    );
END;
$$;

alter function production.imposition_unit_status_update(bigint, integer, integer, text[]) owner to xfw3;

