create table cart_log
(
	cart_log_id bigint generated always as identity
		primary key,
	cart_id bigint not null
		references cart
			on delete cascade,
	moved_at timestamp with time zone default now() not null,
	status text not null,
	-- a movement may expire: from valid_till on the cart is in after_status
	-- until the next row (e.g. reserved -> expired)
	valid_till timestamp with time zone,
	after_status text,
	constraint cart_log_after_status_check
		check ((valid_till is null) = (after_status is null))
);

comment on table cart_log is 'Append-only status movements of a cart. A row may carry an expiry: from valid_till on the cart is in after_status until the next row.';

alter table cart_log owner to xfw3;

create index cart_log_cart_id_moved_at_idx
	on cart_log (cart_id asc, moved_at desc);
