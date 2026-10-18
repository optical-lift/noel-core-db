-- Build 5 connection/consent invariants. No user or Work rows are inserted.
DO $verify$
DECLARE v_name text;
BEGIN
 IF NOT EXISTS(
   SELECT 1 FROM information_schema.columns
   WHERE table_schema='atlas' AND table_name='company_work_standing_assignment_scopes'
     AND column_name='employee_seat_id' AND is_nullable='YES'
 ) THEN
   RAISE EXCEPTION 'Legacy delivery seat still required for an agreed Work scope';
 END IF;
 IF has_table_privilege('authenticated','atlas.company_work_standing_assignment_scopes','SELECT')
    OR has_table_privilege('authenticated','atlas.company_work_standing_assignment_scopes','INSERT')
    OR has_table_privilege('anon','atlas.company_work_standing_assignment_scopes','SELECT') THEN
   RAISE EXCEPTION 'Connection agreement history must remain RPC-only';
 END IF;
 FOREACH v_name IN ARRAY ARRAY[
   'propose_company_work_standing_scope_self_api_v1',
   'respond_company_work_standing_scope_self_api_v1',
   'company_work_standing_scopes_self_api_v1',
   'offer_unallocated_company_work_self_api_v1',
   'respond_unallocated_company_work_self_api_v1',
   'company_work_initial_offers_self_api_v1'
 ] LOOP
   IF NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname=v_name AND NOT p.prosecdef
       AND has_function_privilege('authenticated',p.oid,'EXECUTE')
       AND NOT has_function_privilege('anon',p.oid,'EXECUTE')) THEN
      RAISE EXCEPTION 'Authenticated invoker transport missing for %',v_name;
   END IF;
 END LOOP;
 IF position('organization_employee_seats' IN
   pg_get_functiondef('atlas.propose_company_work_standing_scope_self_api_v1(uuid,uuid,uuid,uuid,text,timestamptz)'::regprocedure))>0
 OR position('organization_employee_seats' IN
   pg_get_functiondef('atlas.respond_company_work_standing_scope_self_api_v1(uuid,text)'::regprocedure))>0
 OR position('organization_employee_seats' IN
   pg_get_functiondef('atlas.guard_work_allocation_responsibility_establishment_v2()'::regprocedure))>0
 OR position('organization_employee_seats' IN
   pg_get_functiondef('atlas.offer_unallocated_company_work_self_api_v1(uuid,uuid,uuid,text)'::regprocedure))>0
 OR position('organization_employee_seats' IN
   pg_get_functiondef('atlas.respond_unallocated_company_work_self_api_v1(uuid,text)'::regprocedure))>0
 THEN RAISE EXCEPTION 'Classification gate remains on institutional Work agreement/offer'; END IF;
 IF position('company_work_native_ledger_owner_self_v1' IN
   pg_get_functiondef('atlas.propose_company_work_standing_scope_self_api_v1(uuid,uuid,uuid,uuid,text,timestamptz)'::regprocedure))=0
 OR position('scope.accepted_by_person_id=worker.person_id' IN
   pg_get_functiondef('atlas.guard_work_allocation_responsibility_establishment_v2()'::regprocedure))=0
 OR position('organization_membership_present_effective_at_v1' IN
   pg_get_functiondef('atlas.respond_company_work_standing_scope_self_api_v1(uuid,text)'::regprocedure))=0
 THEN RAISE EXCEPTION 'Owner, connection, or individual consent guard missing'; END IF;
 IF position('Withdraw or resolve the original individual offer first' IN
   pg_get_functiondef('atlas.manager_assign_company_work_under_standing_scope_self_api_v1(uuid,uuid,text)'::regprocedure))=0
 THEN RAISE EXCEPTION 'Standing scope must not override a pending single-work offer'; END IF;
END
$verify$;
