create table internal_rework
(
	internal_rework_id integer not null
		primary key,
	order_id integer,
	order_log_id integer,
	object_type text not null,
	object_id integer not null,
	object_sequence integer,
	object_reference text,
	object_amount integer,
	production_unit_id integer,
	production_line_id integer,
	internal_status_code text,
	created_at timestamp with time zone not null,
	updated_at timestamp with time zone not null,
	deleted_at timestamp with time zone,
	side text,
	rework_incident_date timestamp with time zone,
	domain_id integer,
	production_orderline_id integer
);

alter table internal_rework owner to xfw3;

create index idx_internal_rework_order_log_id
	on internal_rework (order_log_id);

create index idx_internal_rework_order_id
	on internal_rework (order_id);

create index idx_internal_rework_object_id
	on internal_rework (object_id);

create index idx_internal_rework_object_type
	on internal_rework (object_type);

create index idx_internal_rework_updated_at
	on internal_rework (updated_at);

create index idx_internal_rework_pol_id
	on internal_rework (production_orderline_id);

create index ix_internal_rework_active
	on internal_rework (production_orderline_id)
	where (deleted_at IS NULL);

