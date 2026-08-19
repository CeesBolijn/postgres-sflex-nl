create function get_search_nav() returns TABLE(search_navs jsonb)
	language plpgsql
as $$
BEGIN
    RETURN QUERY SELECT
                     (SELECT nav_json FROM site.nav WHERE nav = 'xfw.main-search') AS search_navs;
END;
$$;

alter function get_search_nav() owner to xfw3;

