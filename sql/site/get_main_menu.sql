create function site.get_main_menu() returns TABLE(nav_left jsonb, nav_right jsonb)
	language plpgsql
as $$
BEGIN
    RETURN QUERY SELECT
                     (SELECT nav_json FROM site.nav WHERE nav = 'xfw.main-menu-left') AS nav_left,
                     (SELECT nav_json FROM site.nav WHERE nav = 'xfw.main-menu-right') AS nav_right;
END;
$$;

alter function site.get_main_menu() owner to xfw3;

