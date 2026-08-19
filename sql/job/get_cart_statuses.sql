create function job.get_cart_statuses(p_cart_ids bigint[], p_at timestamp with time zone DEFAULT now()) returns TABLE(cart_id bigint, status text, since timestamp with time zone)
	stable
	language sql
as $$
    -- the last movement before p_at per cart; when its expiry has passed the
    -- cart is in after_status since that expiry
    select distinct on (l.cart_id)
           l.cart_id,
           case when l.valid_till is not null and p_at > l.valid_till then l.after_status else l.status end,
           case when l.valid_till is not null and p_at > l.valid_till then l.valid_till   else l.moved_at end
    from job.cart_log l
    where l.cart_id = any (p_cart_ids)
      and l.moved_at <= p_at
    order by l.cart_id, l.moved_at desc;
$$;

alter function job.get_cart_statuses(bigint[], timestamp with time zone) owner to xfw3;
