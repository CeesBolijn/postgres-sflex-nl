create sequence unit_manifest_unit_manifest_id_seq;

alter sequence unit_manifest_unit_manifest_id_seq owner to xfw3;

alter sequence unit_manifest_unit_manifest_id_seq owned by spec_unit_manifest.unit_manifest_id;

