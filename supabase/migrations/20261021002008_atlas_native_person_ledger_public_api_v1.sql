-- Atlas Build 5: PostgREST public entry points for released canonical Person/Ledger RPCs.
-- Public schema is the browser Data API surface; atlas schema owns all authority.
-- Invoker-only wrappers preserve the underlying authenticated Person and Ledger guards.
-- No Person, Work, membership, seat, credential or consent records are modified.
BEGIN;

CREATE OR REPLACE FUNCTION public.native_connected_ledger_access_self_api_v1()
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY INVOKER
SET search_path TO ''
AS $function$
  SELECT atlas.native_connected_ledger_access_self_api_v1();
$function$;

CREATE OR REPLACE FUNCTION public.native_ledger_standing_scopes_self_api_v1()
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY INVOKER
SET search_path TO ''
AS $function$
  SELECT atlas.native_ledger_standing_scopes_self_api_v1();
$function$;

CREATE OR REPLACE FUNCTION public.native_ledger_company_units_owner_self_api_v1(p_organization_id uuid, p_ledger_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY INVOKER
SET search_path TO ''
AS $function$
  SELECT atlas.native_ledger_company_units_owner_self_api_v1(p_organization_id, p_ledger_id);
$function$;

CREATE OR REPLACE FUNCTION public.propose_native_ledger_standing_scope_owner_self_api_v1(p_organization_id uuid, p_ledger_id uuid, p_worker_person_id uuid, p_organization_unit_id uuid, p_coverage_mode text, p_operation_class text, p_terms text, p_valid_until timestamptz DEFAULT NULL)
RETURNS jsonb
LANGUAGE sql
VOLATILE SECURITY INVOKER
SET search_path TO ''
AS $function$
  SELECT atlas.propose_native_ledger_standing_scope_owner_self_api_v1(p_organization_id, p_ledger_id, p_worker_person_id, p_organization_unit_id, p_coverage_mode, p_operation_class, p_terms, p_valid_until);
$function$;

CREATE OR REPLACE FUNCTION public.respond_native_ledger_standing_scope_self_api_v1(p_scope_id uuid, p_decision text)
RETURNS jsonb
LANGUAGE sql
VOLATILE SECURITY INVOKER
SET search_path TO ''
AS $function$
  SELECT atlas.respond_native_ledger_standing_scope_self_api_v1(p_scope_id, p_decision);
$function$;

CREATE OR REPLACE FUNCTION public.assign_native_ledger_company_work_under_scope_owner_self_api_v1(p_work_item_id uuid, p_scope_id uuid, p_reason text)
RETURNS jsonb
LANGUAGE sql
VOLATILE SECURITY INVOKER
SET search_path TO ''
AS $function$
  SELECT atlas.assign_native_ledger_company_work_under_scope_owner_self_api_v1(p_work_item_id, p_scope_id, p_reason);
$function$;

REVOKE ALL ON FUNCTION public.native_connected_ledger_access_self_api_v1() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.native_connected_ledger_access_self_api_v1() TO authenticated;
REVOKE ALL ON FUNCTION public.native_ledger_standing_scopes_self_api_v1() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.native_ledger_standing_scopes_self_api_v1() TO authenticated;
REVOKE ALL ON FUNCTION public.native_ledger_company_units_owner_self_api_v1(uuid,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.native_ledger_company_units_owner_self_api_v1(uuid,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.propose_native_ledger_standing_scope_owner_self_api_v1(uuid,uuid,uuid,uuid,text,text,text,timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.propose_native_ledger_standing_scope_owner_self_api_v1(uuid,uuid,uuid,uuid,text,text,text,timestamptz) TO authenticated;
REVOKE ALL ON FUNCTION public.respond_native_ledger_standing_scope_self_api_v1(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.respond_native_ledger_standing_scope_self_api_v1(uuid,text) TO authenticated;
REVOKE ALL ON FUNCTION public.assign_native_ledger_company_work_under_scope_owner_self_api_v1(uuid,uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.assign_native_ledger_company_work_under_scope_owner_self_api_v1(uuid,uuid,text) TO authenticated;

COMMIT;
