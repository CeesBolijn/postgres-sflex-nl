create table calculated_package
(
	calculated_package_id bigint not null
		primary key,
	domain_id integer not null,
	order_id bigint,
	address_country varchar(10),
	deleted_at timestamp with time zone,
	updated_at timestamp with time zone
);

alter table calculated_package owner to xfw3;

