create function get_job_summary(p_user_company_id integer, p_user_domain_id integer) returns TABLE(container_id integer, job text, title text, job_date_time timestamp with time zone, employee text, customer text, delivery_date text, delivery_type text, status jsonb)
	language sql
as $$
SELECT
    1 AS container_id,
    'ABC-2024001' AS job,
    'Sample Job Title' AS title,
    now() AS job_date_time,
    'John Doe' AS employee,
    'Acme Corp, Jane Smith' AS customer,
    '2024-06-01' AS delivery_date,
    'Express' AS delivery_type,
    '{
        "x_bom_state_id": 4,
        "batch_state_id": 1,
        "option_state_id": 2,
        "container_state_id": 4,
        "x_bom_class_name": "initialized",
        "batch_class_name": "paused",
        "option_class_name": "initialized",
        "container_class_name": "initialized",
        "step": "proposal",
        "content": {
            "x_bom_state": "Voorstel",
            "batch_state": "Wachten",
            "option_state": "Optie",
            "container_state": "Voorstel",
            "ml": {
                "en": { "text": "" }
            }
        }
    }'::jsonb AS status;
$$;

alter function get_job_summary(integer, integer) owner to xfw3;

