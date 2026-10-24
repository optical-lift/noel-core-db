-- Disposable production-shaped clone. Historical membership is never
-- deleted; new owner-issued native standing Work no longer fabricates one.
DO $audit$
DECLARE v_source text;
BEGIN
 IF (SELECT is_nullable FROM information_schema.columns
     WHERE table_schema='atlas'
       AND table_name='company_work_standing_assignment_scopes'
       AND column_name='proposed_by_membership_id') IS DISTINCT FROM 'YES'
 THEN RAISE EXCEPTION 'New native standing scope still requires historic owner membership'; END IF;
 SELECT pg_get_functiondef(p.oid) INTO v_source FROM pg_proc p
 JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='atlas'
   AND p.proname='propose_native_ledger_standing_scope_owner_self_api_v1';
 IF v_source ILIKE '%current_effective_organization_membership_v1%' OR
   v_source NOT ILIKE '%company_work_native_ledger_owner_self_v1%' OR
   v_source NOT ILIKE '%v_owner_membership:=NULL%'
 THEN RAISE EXCEPTION 'Propose native scope still admits obsolete owner member gate'; END IF;
 SELECT pg_get_functiondef(p.oid) INTO v_source FROM pg_proc p
 JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='atlas'
   AND p.proname='assign_native_ledger_company_work_under_scope_owner_self_api_v1';
 IF v_source ILIKE '%current_effective_organization_membership_v1%' OR
   v_source NOT ILIKE '%company_work_native_ledger_owner_self_v1%' OR
   v_source NOT ILIKE '%v_owner_membership:=NULL%'
 THEN RAISE EXCEPTION 'Assign native Work still admits obsolete owner member gate'; END IF;
 SELECT pg_get_functiondef(p.oid) INTO v_source FROM pg_proc p
 JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='atlas'
   AND p.proname='guard_work_allocation_responsibility_establishment_v2';
 IF v_source NOT ILIKE '%principal_ledger_authorities%' OR
   v_source NOT ILIKE '%proposed_by_person_id=atlas.current_person_id_v1()%'
 THEN RAISE EXCEPTION 'Guard has no immutable exact signed Person Ledger governance'; END IF;
END
$audit$;
