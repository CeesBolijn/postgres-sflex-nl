create table nest_job
(
	nest_job_id integer generated always as identity
		constraint pk_mock_nest_job
			primary key,
	nest_bucket_id integer,
	waste_perc numeric,
	deadline_fill_perc numeric,
	deadline_at timestamp with time zone,
	width numeric,
	height numeric,
	resource_json jsonb,
	remarks_json jsonb,
	nest_job_guid uuid,
	job_name text,
	amount integer,
	spec_id integer,
	job_thumbnail text,
	mock_batch_id integer,
	mock_nest_id integer
);

alter table nest_job owner to xfw3;

