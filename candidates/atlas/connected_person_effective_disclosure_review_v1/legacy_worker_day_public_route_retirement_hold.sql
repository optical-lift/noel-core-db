-- HOLD / DO NOT EXECUTE — coordinated legacy Worker Day endpoint retirement.
-- These APIs are currently callable under the former farm-hand/employee
-- authority model. Revoking them before source-enforced Person Work reads,
-- approved instructions, assignment/results parity, original history and
-- regression evidence will break legitimate existing worker functionality.
--
-- This is an explicit catalog ACL cutover option for the existing authorization
-- owner in Noel #2255/#2263, NOT a standalone migration or release instruction.
-- A definer wrapper in another reachable schema may still invoke private
-- helpers: exhaustive alternate-route/source proof is separately mandatory.
-- No legacy UI retirement, domain closure, source disposal, grants of new
-- authority or production migration is accomplished by holding this file.
BEGIN;

REVOKE EXECUTE ON FUNCTION public.company_work_worker_day_self_api_v1(date,integer) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION atlas.company_work_worker_day_self_api_v1(date,integer) FROM PUBLIC,anon,authenticated;

REVOKE EXECUTE ON FUNCTION public.company_work_worker_day_refresh_self_api_v1(date,integer) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION atlas.company_work_worker_day_refresh_self_api_v1(date,integer) FROM PUBLIC,anon,authenticated;

REVOKE EXECUTE ON FUNCTION public.worker_report_company_work_projection_self_api_v1(uuid,text,text,jsonb) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION atlas.worker_report_company_work_projection_self_api_v1(uuid,text,text,jsonb) FROM PUBLIC,anon,authenticated;

REVOKE EXECUTE ON FUNCTION public.company_work_employee_home_self_api_v1() FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION atlas.company_work_employee_home_self_api_v1() FROM PUBLIC,anon,authenticated;

COMMIT;
