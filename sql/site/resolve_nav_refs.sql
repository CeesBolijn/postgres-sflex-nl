create function site.resolve_nav_refs(p_node jsonb) returns jsonb
	stable
	language plpgsql
as $$
DECLARE
  v_type   text := jsonb_typeof(p_node);
  v_result jsonb;
  v_key    text;
  v_val    jsonb;
  v_code   text;
  v_nav    jsonb;
BEGIN
    -- =============================================================================
    -- mapping.resolve_nav_refs
    -- Recursively walks a jsonb value and replaces any string "nav:<code>"
    -- found at any depth with mapping.nav.nav_json for that code.
    --
    -- Example: { "nav": "nav:resource_menu" } -> { "nav": { "menu": [...] } }
    --
    -- Note: single-level lookup only, nav_json itself is not scanned for refs.
    -- Unknown codes are left unchanged.
    -- =============================================================================
  IF v_type = 'string' THEN
    IF (p_node #>> '{}') LIKE 'nav:%' THEN
      v_code := substring(p_node #>> '{}' FROM 5);
      SELECT nav_json INTO v_nav FROM site.nav WHERE nav = v_code;
      RETURN COALESCE(v_nav, p_node); -- geen match: onveranderd terug
    END IF;
    RETURN p_node;

  ELSIF v_type = 'object' THEN
    v_result := '{}'::jsonb;
    FOR v_key, v_val IN SELECT * FROM jsonb_each(p_node) LOOP
      v_result := v_result || jsonb_build_object(v_key, site.resolve_nav_refs(v_val));
    END LOOP;
    RETURN v_result;

  ELSIF v_type = 'array' THEN
    RETURN COALESCE(
      (SELECT jsonb_agg(site.resolve_nav_refs(elem)) FROM jsonb_array_elements(p_node) elem),
      '[]'::jsonb
    );

  ELSE
    RETURN p_node;
  END IF;
END;
$$;

alter function site.resolve_nav_refs(jsonb) owner to xfw3;

