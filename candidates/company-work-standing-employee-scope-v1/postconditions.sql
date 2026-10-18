-- No user rows or standing agreements are inserted by this validation.
DO $postconditions$
DECLARE v_name text;
BEGIN
 IF to_regclass('atlas.company_work_standing_assignment_scopes') IS NULL
 THEN RAISE EXCEPTION 'Missing worker-accepted standing scope relation'; END IF;
 IF has_table_privilege('anon','atlas.company_work_standing_assignment_scopes','SELECT')
    OR has_table_privilege('authenticated','atlas.company_work_standing_assignment_scopes','SELECT')
    OR has_table_privilege('authenticated','atlas.company_work_standing_assignment_scopes','INSERT') THEN
   RAISE EXCEPTION 'Standing scope relation must remain private'; END IF;
 FOREACH v_name IN ARRAY ARRAY[
   'propose_company_work_standing_scope_self_api_v1',
   'respond_company_work_standing_scope_self_api_v1',
   'revoke_company_work_standing_scope_self_api_v1',
   'company_work_standing_scopes_self_api_v1',
   'manager_assign_company_work_under_standing_scope_self_api_v1'
 ] LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname=v_name AND NOT p.prosecdef
      AND has_function_privilege('authenticated',p.oid,'EXECUTE')
      AND NOT has_function_privilege('anon',p.oid,'EXECUTE'))
  THEN RAISE EXCEPTION 'Missing authenticated invoker-only guarded transport: %',v_name; END IF;
 END LOOP;
 IF position('delegated_under_standing_scope' IN
   pg_get_functiondef('atlas.guard_work_allocation_responsibility_establishment_v2()'::regprocedure))=0
 THEN RAISE EXCEPTION 'No governed delegated establishment basis in allocation guard'; END IF;
 IF position('scope.accepted_by_person_id=worker.person_id' IN
   pg_get_functiondef('atlas.guard_work_allocation_responsibility_establishment_v2()'::regprocedure))=0
 THEN RAISE EXCEPTION 'Allocation guard must verify authentic worker scope consent'; END IF;
 IF position('company_work_native_ledger_owner_self_v1' IN
   pg_get_functiondef('atlas.propose_company_work_standing_scope_self_api_v1(uuid,uuid,uuid,uuid,text,timestamptz)'::regprocedure))=0
 THEN RAISE EXCEPTION 'Owner proposal missing dual root Ledger authority'; END IF;
 IF position('company_work_native_ledger_owner_self_v1' IN
   pg_get_functiondef('atlas.manager_assign_company_work_under_standing_scope_self_api_v1(uuid,uuid,text)'::regprocedure))=0
 THEN RAISE EXCEPTION 'Owner direct assignment missing dual root Ledger authority'; END IF;
 IF position('Withdraw or resolve the original individual offer first' IN
   pg_get_functiondef('atlas.manager_assign_company_work_under_standing_scope_self_api_v1(uuid,uuid,text)'::regprocedure))=0
 THEN RAISE EXCEPTION 'Standing scope must not override preexisting pending individual offer'; END IF;
 IF position('p_decision' IN
   pg_get_functiondef('atlas.respond_company_work_standing_scope_self_api_v1(uuid,text)'::regprocedure))=0
 THEN RAISE EXCEPTION 'Worker must explicitly accept or decline standing authority'; END IF;
END
$postconditions$;
