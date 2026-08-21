select table_name, string_agg(column_name, ', ' order by ordinal_position) as columns
from information_schema.columns
where table_schema = 'site'
group by table_name
order by table_name;

-- staat de naam ergens in een tabel van site (kolommen van type text/jsonb)?
select n.nspname, p.proname
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where p.proname in ('get_timeline_view_segments', 'get_print_schedule_materials', 'get_production_orderline_manifest');