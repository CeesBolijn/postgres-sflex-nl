create function mapping.get_unit_manifest_aggregate(p_production_orderline_ids integer[], p_scope text DEFAULT NULL::text) returns TABLE(production_orderline_id integer, scope text, option_codes text[], i18n jsonb)
	language plpgsql
as $$
#variable_conflict use_column
BEGIN
    -- Aggregate manifest rows per orderline and scope, concatenating i18n labels.
    -- p_scope NULL returns all scopes.
    RETURN QUERY
    SELECT   m.production_orderline_id,
             m.scope,
             array_agg(m.option_code ORDER BY m.sort_order, m.unit_manifest_id) AS option_codes,
             jsonb_strip_nulls(jsonb_build_object(
                 'en', jsonb_build_object('label',
                     string_agg(m.config_json -> 'i18n' -> 'en' ->> 'abb', ' '
                                ORDER BY m.sort_order, m.unit_manifest_id)),
                 'nl', jsonb_build_object('label',
                     string_agg(m.config_json -> 'i18n' -> 'nl' ->> 'abb', ' '
                                ORDER BY m.sort_order, m.unit_manifest_id))
             )) AS i18n
    FROM     mapping.spec_unit_manifest m
    WHERE    m.production_orderline_id = ANY(p_production_orderline_ids)
      AND    m.scope IS NOT DISTINCT FROM coalesce(p_scope, m.scope)
    GROUP BY m.production_orderline_id, m.scope;
END;
$$;

alter function mapping.get_unit_manifest_aggregate(integer[], text) owner to xfw3;

