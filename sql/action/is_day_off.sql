create function action.is_day_off(p_tenants_off integer[], p_tenant_ids integer[] DEFAULT NULL::integer[]) returns boolean
	immutable
	parallel safe
	language sql
as $$
    -- A date counts as a mandatory day off for the caller when every tenant
    -- the caller looks at has the day off (dates.tenants_mandatory_day_off);
    -- without a tenant scope, when any tenant has the day off.
    select case when p_tenant_ids is null
                then cardinality(coalesce(p_tenants_off, '{}')) > 0
                else p_tenant_ids <@ coalesce(p_tenants_off, '{}') end;
$$;

alter function action.is_day_off(integer[], integer[]) owner to xfw3;
