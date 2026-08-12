create table ticket
(
	ticket_id integer not null
		primary key,
	domain_id integer not null,
	order_id integer,
	order_number integer,
	customer_id integer,
	production_line_id integer,
	production_order_id integer,
	type_code varchar(25),
	type_name varchar(50),
	status varchar(255),
	priority varchar(255),
	credit_status varchar(255),
	credit_amount numeric(8,2),
	title varchar(255),
	action_item varchar(255),
	objects_json jsonb,
	created_at timestamp with time zone,
	closed_at timestamp with time zone,
	solved_at timestamp with time zone,
	deleted_at timestamp with time zone,
	updated_at timestamp with time zone
);

alter table ticket owner to xfw3;

create index idx_ticket_order_id
	on ticket (order_id);

create index idx_ticket_created_at
	on ticket (created_at);

create index idx_ticket_updated_at
	on ticket (updated_at);

