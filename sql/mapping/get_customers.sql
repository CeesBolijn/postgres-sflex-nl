-- return type changes, so the old signatures have to go first
drop function if exists mapping.get_customers(text);

create function mapping.get_customers(p_search text DEFAULT NULL::text) returns TABLE(customer_id integer, company_name text, production_line_ids jsonb)
	stable
	language plpgsql
as $$
#variable_conflict use_column
begin
    return query
    select c.customer_id, c.company_name,
           -- the lines this customer has open work on, so picking a customer
           -- narrows the line filter along with it. Same column the boards
           -- filter on (first_production_line_id). jsonb, not integer[]: the
           -- api turns a postgres array into an object keyed by index.
           coalesce(jsonb_agg(distinct cs.first_production_line_id)
                    filter (where cs.first_production_line_id is not null),
                    '[]'::jsonb)
    from mapping.customer c
    -- the join is the filter as well: only customers with work in progress,
    -- because the filter narrows a board. Rides ix_component_specs_board
    -- (is_open leading, customer_id and first_production_line_id included).
    join mapping.component_specs cs
      on cs.customer_id = c.customer_id
     and cs.is_open
    where p_search is null or c.company_name ilike '%' || p_search || '%'
    group by c.customer_id, c.company_name
    order by c.company_name
    limit 50;
end;
$$;

alter function mapping.get_customers(text) owner to xfw3;
