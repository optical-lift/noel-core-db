-- Structural and access postconditions against an isolated production-schema clone.
DO $verify$
DECLARE
  v_def text;
BEGIN
  IF to_regclass('atlas.company_work_legacy_slice_contract_provenance_v1') IS NULL
  THEN RAISE EXCEPTION 'Missing legacy slice source provenance audit'; END IF;
  IF NOT EXISTS(
    SELECT 1 FROM pg_class c
    WHERE c.oid='atlas.company_work_legacy_slice_contract_provenance_v1'::regclass
      AND c.relrowsecurity
  ) THEN RAISE EXCEPTION 'Legacy slice provenance must be RLS-enabled'; END IF;
  IF has_table_privilege('anon','atlas.company_work_legacy_slice_contract_provenance_v1','SELECT')
    OR has_table_privilege('authenticated','atlas.company_work_legacy_slice_contract_provenance_v1','SELECT')
    OR has_table_privilege('authenticated','atlas.company_work_legacy_slice_contract_provenance_v1','INSERT')
  THEN RAISE EXCEPTION 'Source provenance is privileged, RPC-only audit'; END IF;
  IF to_regprocedure('atlas.bind_legacy_task_slice_result_contract_self_api_v1(uuid,uuid,uuid,text)') IS NULL
    OR to_regprocedure('public.bind_legacy_task_slice_result_contract_self_api_v1(uuid,uuid,uuid,text)') IS NULL
  THEN RAISE EXCEPTION 'Legacy slice result contract APIs missing'; END IF;
  IF NOT EXISTS(
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname='bind_legacy_task_slice_result_contract_self_api_v1'
      AND NOT p.prosecdef AND has_function_privilege('authenticated',p.oid,'EXECUTE')
      AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
  ) THEN RAISE EXCEPTION 'Public transport must be authenticated security invoker'; END IF;
  IF NOT EXISTS(
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='atlas'
      AND p.proname='bind_legacy_task_slice_result_contract_self_api_v1'
      AND p.prosecdef AND has_function_privilege('authenticated',p.oid,'EXECUTE')
      AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
  ) THEN RAISE EXCEPTION 'Guarded internal binding function permissions missing'; END IF;
  v_def:=pg_get_functiondef(
    'atlas.bind_legacy_task_slice_result_contract_self_api_v1(uuid,uuid,uuid,text)'::regprocedure);
  IF position('company_work_native_ledger_owner_self_v1' IN v_def)=0
    OR position('current_effective_organization_membership_v1' IN v_def)=0
    OR position('member.role=''owner''' IN v_def)=0
    OR position('v_work.source_object_type IS DISTINCT FROM ''legacy_task_slice''' IN v_def)=0
    OR position('src.id=v_work.source_object_id' IN v_def)=0
    OR position('src.organization_id=p_organization_id' IN v_def)=0
    OR position('sliceOfLegacyTask' IN v_def)=0
    OR position('deliveryKey' IN v_def)=0
    OR position('company_work_native_ledger_exact_source_v1' IN v_def)=0
    OR position('attribution_state=''active''' IN v_def)=0
    OR position('work_execution_results' IN v_def)=0
    OR position('result_contract_key IS NULL' IN v_def)=0
    OR position('company_work_legacy_slice_contract_provenance_v1' IN v_def)=0
  THEN RAISE EXCEPTION 'Legacy slice source, owner, Ledger or audit proof weakened'; END IF;
  IF NOT EXISTS(
    SELECT 1 FROM atlas.work_result_contract_policies
    WHERE contract_key='ordinary_company_work_manager_acceptance_v1'
      AND active AND acceptance_mode='manager_acceptance'
      AND source_domain='organization'
  ) THEN RAISE EXCEPTION 'Existing manager acceptance policy unavailable'; END IF;
  IF position('v_work.source_object_type<>''legacy_task''' IN
    pg_get_functiondef('atlas.bind_ordinary_company_work_result_contract_self_api_v1(uuid,uuid,uuid,text)'::regprocedure))=0
  THEN RAISE EXCEPTION 'Ordinary-only API must still reject legacy task slices'; END IF;
END
$verify$;
