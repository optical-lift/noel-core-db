-- Schema-only postconditions for the native Ledger standing assignment candidate.
-- Run on an authorized disposable production-shaped clone AFTER candidate migration.
-- Authenticated human end-to-end and negative jurisdiction tests are separate;
-- this file never fabricates a person's consent or writes private user records.
DO $post$
DECLARE v_count integer;
BEGIN
 IF (SELECT is_nullable FROM information_schema.columns
       WHERE table_schema='atlas' AND table_name='company_work_standing_assignment_scopes'
         AND column_name='worker_membership_id') <> 'YES' OR
    (SELECT is_nullable FROM information_schema.columns
       WHERE table_schema='atlas' AND table_name='company_work_standing_assignment_scopes'
         AND column_name='position_id') <> 'YES' OR
    (SELECT is_nullable FROM information_schema.columns
       WHERE table_schema='atlas' AND table_name='company_work_standing_assignment_scopes'
         AND column_name='position_appointment_id') <> 'YES' THEN
   RAISE EXCEPTION 'Native standing scope cannot exist without a legacy appointment';
 END IF;

 SELECT count(*) INTO v_count FROM pg_proc p
 JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='atlas' AND p.proname IN (
   'propose_native_ledger_standing_scope_owner_self_api_v1',
   'respond_native_ledger_standing_scope_self_api_v1',
   'native_ledger_standing_scopes_self_api_v1',
   'native_ledger_company_units_owner_self_api_v1',
   'assign_native_ledger_company_work_under_scope_owner_self_api_v1');
 IF v_count<>5 THEN RAISE EXCEPTION 'Native Ledger RPC set incomplete: %',v_count; END IF;

 IF NOT EXISTS (SELECT 1 FROM pg_constraint c
   WHERE c.conrelid='atlas.work_allocations'::regclass
     AND c.conname='work_allocations_exact_assignee_carrier_v1'
     AND pg_get_constraintdef(c.oid) LIKE '%delegated_under_standing_scope%') THEN
   RAISE EXCEPTION 'Person-native direct Work allocation shape not admitted';
 END IF;

 IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='atlas' AND p.proname='guard_work_allocation_responsibility_establishment_v2'
     AND pg_get_functiondef(p.oid) LIKE '%Exact canonical Person standing-scope provenance required%')
 THEN RAISE EXCEPTION 'Source-backed responsibility trigger not migrated'; END IF;

 IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='atlas' AND p.proname='connected_person_company_work_today_self_api_v1'
     AND pg_get_functiondef(p.oid) LIKE '%establishmentBasisKind%')
 THEN RAISE EXCEPTION 'Person notebook read does not distinguish direct assignment'; END IF;

 IF to_regclass('atlas.organization_employee_seats') IS NULL THEN
   RAISE EXCEPTION 'Unexpected early legacy seat deletion: separate credential migration required';
 END IF;
END
$post$;
