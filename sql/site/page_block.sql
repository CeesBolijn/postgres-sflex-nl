create table page_block
(
	page_id integer not null
		references page
			on delete cascade,
	block_id integer not null
		references block
			on delete cascade,
	sort_order integer,
	primary key (block_id, page_id)
);

alter table page_block owner to xfw3;

