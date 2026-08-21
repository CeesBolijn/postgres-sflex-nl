create function relation.get_root_parent_company_id(p_company_id integer, p_domain_id integer) returns integer
	language sql
as $$
    SELECT company_id
    FROM relation.company_domain
    WHERE domain_id = p_domain_id
      AND parent_company_id IS NULL
    LIMIT 1;
$$;

alter function relation.get_root_parent_company_id(integer, integer) owner to xfw3;

