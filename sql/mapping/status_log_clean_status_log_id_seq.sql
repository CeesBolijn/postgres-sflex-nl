create sequence status_log_clean_status_log_id_seq;

alter sequence status_log_clean_status_log_id_seq owner to xfw3;

alter sequence status_log_clean_status_log_id_seq owned by status_log.status_log_id;

