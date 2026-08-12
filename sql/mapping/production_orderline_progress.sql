create table production_orderline_progress
(
	production_orderline_id integer not null
		primary key,
	domain_id integer not null,
	status_path integer[],
	status_times integer[],
	part_statuses integer[],
	updated_at timestamp with time zone default CURRENT_TIMESTAMP,
	part_amount integer[],
	operation_progress_status_sequences integer[],
	operation_progress_remaining_amounts integer[]
);

alter table production_orderline_progress owner to xfw3;

create index idx_pol_progress_updated
	on production_orderline_progress (updated_at);

create index ix_production_orderline_progress_id
	on production_orderline_progress (production_orderline_id);

