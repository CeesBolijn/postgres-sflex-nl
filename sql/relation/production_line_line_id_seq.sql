create sequence production_line_line_id_seq
	as integer;

alter sequence production_line_line_id_seq owner to xfw3;

alter sequence production_line_line_id_seq owned by production_line.line_id;

