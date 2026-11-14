-- UNI-OPS-01 / source-exact LIVE public adapter recovery for disposable tests.
-- Read-only pg_get_functiondef + pg_proc.acl from current Noel, 2026-11-05.
-- These wrappers exist in live Noel and are absent from RiverSong's older
-- schema clone. The private scope sources, source grants and Ledger owner
-- guards MUST already exist; do not create/relax those from a test harness.
-- Source-only held candidate, no migration and no production mutation.
DO $dependencies$
BEGIN
 IF to_regprocedure(
  'atlas.propose_native_ledger_standing_scope_owner_self_api_v1(uuid,uuid,uuid,uuid,text,text,text,timestamptz)'
 ) IS NULL
 OR to_regprocedure(
  'atlas.respond_native_ledger_standing_scope_self_api_v1(uuid,text)'
 ) IS NULL THEN
   RAISE EXCEPTION 'STOP native standing Person consent source absent; no synthetic authorization';
 END IF;
 IF NOT has_function_privilege('authenticated',
  'atlas.propose_native_ledger_standing_scope_owner_self_api_v1(uuid,uuid,uuid,uuid,text,text,text,timestamptz)','EXECUTE')
 OR NOT has_function_privilege('authenticated',
  'atlas.respond_native_ledger_standing_scope_self_api_v1(uuid,text)','EXECUTE')
 THEN
   RAISE EXCEPTION 'STOP underlying signed native scope authority grant missing';
 END IF;
END;$dependencies$;

-- Exact current live SECURITY INVOKER adapter. All authority is in atlas.
CREATE OR REPLACE FUNCTION public.propose_native_ledger_standing_scope_owner_self_api_v1(
 p_organization_id uuid, p_ledger_id uuid, p_worker_person_id uuid,
 p_organization_unit_id uuid, p_coverage_mode text, p_operation_class text,
 p_terms text, p_valid_until timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  SELECT atlas.propose_native_ledger_standing_scope_owner_self_api_v1(
   p_organization_id,p_ledger_id,p_worker_person_id,p_organization_unit_id,
   p_coverage_mode,p_operation_class,p_terms,p_valid_until);
$function$;

CREATE OR REPLACE FUNCTION public.respond_native_ledger_standing_scope_self_api_v1(
 p_scope_id uuid,p_decision text
) RETURNS jsonb
LANGUAGE sql
SET search_path TO ''
AS $function$
  SELECT atlas.respond_native_ledger_standing_scope_self_api_v1(
    p_scope_id,p_decision);
$function$;

-- Match the current live ACL precisely, never grant anon/Public execution.
REVOKE ALL ON FUNCTION public.propose_native_ledger_standing_scope_owner_self_api_v1(
 uuid,uuid,uuid,uuid,text,text,text,timestamptz)
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.respond_native_ledger_standing_scope_self_api_v1(
 uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.propose_native_ledger_standing_scope_owner_self_api_v1(
 uuid,uuid,uuid,uuid,text,text,text,timestamptz) TO authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.respond_native_ledger_standing_scope_self_api_v1(
 uuid,text) TO authenticated,service_role;

DO $assert$
BEGIN
 IF has_function_privilege('anon',
  'public.propose_native_ledger_standing_scope_owner_self_api_v1(uuid,uuid,uuid,uuid,text,text,text,timestamptz)','EXECUTE')
 OR has_function_privilege('anon',
  'public.respond_native_ledger_standing_scope_self_api_v1(uuid,text)','EXECUTE')
 OR (SELECT p.prosecdef FROM pg_proc p
     WHERE p.oid='public.propose_native_ledger_standing_scope_owner_self_api_v1(uuid,uuid,uuid,uuid,text,text,text,timestamptz)'::regprocedure)
 OR (SELECT p.prosecdef FROM pg_proc p
     WHERE p.oid='public.respond_native_ledger_standing_scope_self_api_v1(uuid,text)'::regprocedure)
 THEN RAISE EXCEPTION 'STOP recovered public scope adapter broadened access';
 END IF;
 RAISE NOTICE 'PASS current live native scope public adapters, authenticated only, security invoker';
END;$assert$;
