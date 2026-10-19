-- Run only after candidate on a disposable production-schema clone.
-- No real Work, source Tasks, people, sessions or results are inserted.
DO $verify$
DECLARE
 v_name text;
 v_impact_def text;
 v_retire_def text;
 v_guard_def text;
BEGIN
 IF to_regclass('atlas.company_work_retirement_requirement_transfers_v1') IS NULL
 THEN RAISE EXCEPTION 'Append-only retirement reconciliation audit missing'; END IF;
 IF to_regclass('atlas.company_work_retirement_time_contract_cancellations_v1') IS NULL
 THEN RAISE EXCEPTION 'Obsolete time contract cancellation audit missing'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_class
    WHERE oid='atlas.company_work_retirement_requirement_transfers_v1'::regclass
      AND relrowsecurity)
 THEN RAISE EXCEPTION 'Retirement audit RLS must be enabled'; END IF;
 IF has_table_privilege('anon','atlas.company_work_retirement_requirement_transfers_v1','SELECT')
   OR has_table_privilege('authenticated',
       'atlas.company_work_retirement_requirement_transfers_v1','SELECT')
   OR has_table_privilege('authenticated',
       'atlas.company_work_retirement_requirement_transfers_v1','INSERT')
   OR has_table_privilege('authenticated',
       'atlas.company_work_retirement_requirement_transfers_v1','UPDATE')
 THEN RAISE EXCEPTION 'Reconciliation evidence cannot be client writable'; END IF;
 IF has_table_privilege('authenticated',
   'atlas.company_work_retirement_time_contract_cancellations_v1','INSERT')
 OR has_table_privilege('anon',
   'atlas.company_work_retirement_time_contract_cancellations_v1','SELECT')
 THEN RAISE EXCEPTION 'Time contract cancellation evidence must be private'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_constraint
   WHERE conrelid='atlas.company_work_retirement_requirement_transfers_v1'::regclass
     AND contype='u' AND pg_get_constraintdef(oid) LIKE '%source_requirement_link_id%')
 THEN RAISE EXCEPTION 'Duplicate resolution audit guard missing'; END IF;

 FOREACH v_name IN ARRAY ARRAY[
   'company_work_retirement_preflight_self_api_v1(uuid)',
   'retire_company_work_with_reconciliation_self_api_v1(uuid,text,jsonb,text)'
 ] LOOP
   IF NOT EXISTS(SELECT 1 FROM pg_proc p
       WHERE p.oid=to_regprocedure('public.'||v_name)
         AND NOT p.prosecdef
         AND has_function_privilege('authenticated',p.oid,'EXECUTE')
         AND NOT has_function_privilege('anon',p.oid,'EXECUTE'))
   THEN RAISE EXCEPTION 'Authenticated invoker transport absent for %',v_name;
   END IF;
   IF NOT EXISTS(SELECT 1 FROM pg_proc p
       WHERE p.oid=to_regprocedure('atlas.'||v_name)
         AND p.prosecdef
         AND has_function_privilege('authenticated',p.oid,'EXECUTE')
         AND NOT has_function_privilege('anon',p.oid,'EXECUTE'))
   THEN RAISE EXCEPTION 'Guarded internal owner command absent for %',v_name;
   END IF;
 END LOOP;
 IF has_function_privilege('anon',
    'atlas.company_work_retirement_dependency_snapshot_v1(uuid)'::regprocedure,'EXECUTE')
 OR has_function_privilege('authenticated',
    'atlas.company_work_retirement_dependency_snapshot_v1(uuid)'::regprocedure,'EXECUTE')
 THEN RAISE EXCEPTION 'Internal dependency enumerator must not bypass owner'; END IF;

 IF NOT EXISTS(SELECT 1 FROM pg_trigger
   WHERE tgrelid='atlas.work_items'::regclass
     AND tgname='guard_company_work_cancel_dependencies_v1' AND tgenabled='O')
 THEN RAISE EXCEPTION 'All-path cancellation dependency guard missing'; END IF;
 v_guard_def:=pg_get_functiondef(
   'atlas.guard_company_work_cancel_dependencies_v1()'::regprocedure);
 v_impact_def:=pg_get_functiondef(
   'atlas.company_work_retirement_dependency_snapshot_v1(uuid)'::regprocedure);
 v_retire_def:=pg_get_functiondef(
   'atlas.retire_company_work_with_reconciliation_self_api_v1(uuid,text,jsonb,text)'::regprocedure);
 IF position('work_requirement_links' IN v_impact_def)=0
   OR position('work_item_relations' IN v_impact_def)=0
   OR position('company_work_initial_responsibility_offers' IN v_impact_def)=0
   OR position('company_work_participation_offers' IN v_impact_def)=0
   OR position('company_work_responsibility_transfer_offers' IN v_impact_def)=0
   OR position('worker_week_projection_sources' IN v_impact_def)=0
   OR position('work_execution_results' IN v_impact_def)=0
   OR position('work_time_contracts' IN v_impact_def)=0
 THEN RAISE EXCEPTION 'Retirement preflight incomplete'; END IF;
 IF position('company_work_retirement_dependency_snapshot_v1' IN v_guard_def)=0
   OR position('requires dependency reconciliation' IN v_guard_def)=0
 THEN RAISE EXCEPTION 'Cancellation bypass guard missing'; END IF;
 IF position('FOR UPDATE' IN v_retire_def)=0
   OR position('md5(v_impact::text)<>p_impact_token' IN v_retire_def)=0
   OR position('v_target.source_object_id IS DISTINCT FROM v_work.source_object_id' IN v_retire_def)=0
   OR position('company_work_retirement_requirement_transfers_v1' IN v_retire_def)=0
   OR position('company_work_retirement_time_contract_cancellations_v1' IN v_retire_def)=0
   OR position('v_time_contract.source_kind IS DISTINCT FROM ''legacy_task''' IN v_retire_def)=0
   OR position('organization_management_adjudicate_company_work_api_v1' IN v_retire_def)=0
   OR position('sourceTaskPreserved' IN v_retire_def)=0
 THEN RAISE EXCEPTION 'Owner mutation lacks concurrency, proof, provenance or guarded cancellation'; END IF;
 IF position('work_execution_results' IN v_retire_def)>0
   OR position('UPDATE atlas.tasks' IN v_retire_def)>0
   OR position('DELETE FROM atlas.work_items' IN v_retire_def)>0
 THEN RAISE EXCEPTION 'Retirement cannot fabricate worker results, change shared Task or delete Work'; END IF;
 -- Retirement must observe its own requirement/time-contract mutations before
 -- the guard runs; STABLE would reuse the command's original snapshot.
 IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE
   p.oid='atlas.company_work_retirement_dependency_snapshot_v1(uuid)'::regprocedure
     AND p.provolatile='v')
 THEN RAISE EXCEPTION 'Dependency snapshot must see intra-command reconciliation'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE
   p.oid='atlas.company_work_retirement_preflight_self_api_v1(uuid)'::regprocedure
     AND p.provolatile='s')
 THEN RAISE EXCEPTION 'Owner preflight must be non-mutating'; END IF;
END
$verify$;
