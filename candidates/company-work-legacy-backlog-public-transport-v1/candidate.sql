-- Build 5 integration repair: expose previously released owner-gated Venue backlog APIs
-- through the same authenticated public transport used by the Atlas notebook.
-- No legacy Task, canonical Work, Person, or Ledger rows are modified.
BEGIN;

CREATE OR REPLACE FUNCTION public.company_work_legacy_backlog_owner_self_api_v1(
  p_organization_id uuid,
  p_ledger_id uuid,
  p_source_zone text DEFAULT 'Venue',
  p_limit integer DEFAULT 100,
  p_after_task_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO ''
AS $function$
  SELECT atlas.company_work_legacy_backlog_owner_self_api_v1(
    p_organization_id,p_ledger_id,p_source_zone,p_limit,p_after_task_id
  );
$function$;
REVOKE ALL ON FUNCTION public.company_work_legacy_backlog_owner_self_api_v1(
  uuid,uuid,text,integer,uuid
) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.company_work_legacy_backlog_owner_self_api_v1(
  uuid,uuid,text,integer,uuid
) TO authenticated;

CREATE OR REPLACE FUNCTION public.decide_company_work_legacy_backlog_owner_self_api_v1(
  p_organization_id uuid,
  p_ledger_id uuid,
  p_source_task_id uuid,
  p_source_zone text,
  p_expected_source_title text,
  p_decision text,
  p_reason text,
  p_new_work_title text DEFAULT NULL,
  p_existing_work_item_id uuid DEFAULT NULL,
  p_confirm_distinct_current_work boolean DEFAULT false
) RETURNS jsonb
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO ''
AS $function$
  SELECT atlas.decide_company_work_legacy_backlog_owner_self_api_v1(
    p_organization_id,p_ledger_id,p_source_task_id,p_source_zone,
    p_expected_source_title,p_decision,p_reason,p_new_work_title,
    p_existing_work_item_id,p_confirm_distinct_current_work
  );
$function$;
REVOKE ALL ON FUNCTION public.decide_company_work_legacy_backlog_owner_self_api_v1(
  uuid,uuid,uuid,text,text,text,text,text,uuid,boolean
) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.decide_company_work_legacy_backlog_owner_self_api_v1(
  uuid,uuid,uuid,text,text,text,text,text,uuid,boolean
) TO authenticated;

-- PostgREST caches function signatures. The newly created public routes must
-- become visible without a web-app deployment or a data mutation.
NOTIFY pgrst, 'reload schema';

COMMIT;
