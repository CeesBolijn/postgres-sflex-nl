create sequence nest_log_nest_log_id_seq;

alter sequence nest_log_nest_log_id_seq owner to xfw3;

alter sequence nest_log_nest_log_id_seq owned by imposition_log.imposition_log_id;

