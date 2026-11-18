-- U1.9 TEST ONLY — protected disposable schema-clone postconditions.
-- No DDL/DML; no production user/customer rows; not a migration or grant.
-- The clone uses read-only production schema+role snapshots, not source data.
DO $u1_protected_shape$
DECLARE
 name text;
 signature text;
 actual oid;
 tables text[]:=ARRAY[
  'titus.institution_account_admissions_v1',
  'titus.institution_account_admission_withdrawals_v1',
  'titus.institution_account_invitations_v1',
  'titus.institution_account_invitation_cancellations_v1',
  'titus.institution_account_manager_governance_v1',
  'titus.institution_account_root_origins_v1',
  'titus.institution_account_root_transfer_invitations_v1',
  'titus.institution_account_root_transfer_cancellations_v1',
  'titus.institution_account_root_endings_v1'
 ];
 public_rpcs text[]:=ARRAY[
  'public.titus_account_contexts_self_api_v1()',
  'public.titus_account_context_check_self_api_v1(text,uuid)',
  'public.titus_institution_account_self_service_self_api_v1()',
  'public.titus_institution_account_invite_self_api_v1(uuid,uuid,uuid)',
  'public.titus_institution_account_accept_self_api_v1(uuid,uuid)',
  'public.titus_institution_account_withdraw_self_api_v1(uuid,uuid)',
  'public.titus_institution_account_cancel_invite_self_api_v1(uuid,uuid)',
  'public.shared_titus_institution_manager_command_self_api_v1(uuid,text,uuid,uuid,uuid)',
  'public.shared_titus_institution_root_bootstrap_self_api_v1(uuid,uuid,uuid)',
  'public.shared_titus_institution_root_nominate_self_api_v1(uuid,uuid,uuid,uuid)',
  'public.shared_titus_institution_root_accept_self_api_v1(uuid,uuid)',
  'public.shared_titus_institution_root_cancel_self_api_v1(uuid,uuid)',
  'public.shared_titus_institution_root_relinquish_self_api_v1(uuid,uuid,uuid)'
 ];
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved'
 THEN RAISE EXCEPTION 'held U1.9 postconditions need approved disposable clone'
 USING ERRCODE='42501'; END IF;
 IF to_regprocedure('atlas.company_work_native_ledger_owner_self_v1(uuid,uuid)') IS NULL
 OR to_regprocedure('reality.resolve_responsibility_relation_v1(uuid,text,text,text,uuid,text,jsonb)') IS NULL
 OR to_regprocedure('reality.guard_responsibility_relation_v1()') IS NULL
 THEN RAISE EXCEPTION 'canonical Atlas/Reality sources not restored'
 USING ERRCODE='42501'; END IF;
 IF to_regprocedure('atlas.current_person_for_private_course_v1()') IS NULL
 OR has_function_privilege('anon',
    'atlas.current_person_for_private_course_v1()','EXECUTE')
 OR has_function_privilege('authenticated',
    'atlas.current_person_for_private_course_v1()','EXECUTE')
 THEN RAISE EXCEPTION 'held canonical Person adapter has wrong function ACL'
 USING ERRCODE='42501'; END IF;
 FOREACH name IN ARRAY tables LOOP
  actual:=to_regclass(name);
  IF actual IS NULL OR NOT EXISTS(
   SELECT 1 FROM pg_catalog.pg_class c
   WHERE c.oid=actual AND c.relrowsecurity AND NOT c.relforcerowsecurity
  ) THEN RAISE EXCEPTION 'held U1.9 private table RLS not verified'
   USING ERRCODE='42501'; END IF;
  IF has_table_privilege('anon',actual,'SELECT')
  OR has_table_privilege('authenticated',actual,'SELECT')
  OR has_table_privilege('anon',actual,'INSERT')
  OR has_table_privilege('authenticated',actual,'INSERT')
  THEN RAISE EXCEPTION 'held U1.9 private table direct grant leaked'
  USING ERRCODE='42501'; END IF;
 END LOOP;
 FOREACH signature IN ARRAY public_rpcs LOOP
  actual:=to_regprocedure(signature);
  IF actual IS NULL
   OR has_function_privilege('anon',actual,'EXECUTE')
   OR NOT has_function_privilege('authenticated',actual,'EXECUTE')
  THEN RAISE EXCEPTION 'held U1.9 signed RPC ACL mismatch'
  USING ERRCODE='42501'; END IF;
 END LOOP;
 -- A restored schema snapshot contains no customer rows. Verify we have not
 -- removed original legacy table names (not a historical no-loss test).
 IF to_regclass('titus.customer_workspaces_v1') IS NULL
 OR to_regclass('titus.customer_course_drafts_v1') IS NULL
 OR to_regclass('titus.customer_workspace_entitlements_v1') IS NULL
 THEN RAISE EXCEPTION 'legacy Titus structural names missing after candidate'
 USING ERRCODE='42501'; END IF;
 RAISE NOTICE 'PASS held U1.9 protected schema shape/RLS/RPC ACL only: NOT signed behavior or release';
END $u1_protected_shape$;
