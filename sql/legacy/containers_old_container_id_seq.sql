create sequence containers_old_container_id_seq;

alter sequence containers_old_container_id_seq owner to xfw3;

alter sequence containers_old_container_id_seq owned by containers.container_id;

