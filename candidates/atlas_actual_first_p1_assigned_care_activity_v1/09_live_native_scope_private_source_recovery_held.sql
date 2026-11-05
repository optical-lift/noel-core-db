-- Held Noel UNI-OPS P1 exact LIVE native standing-scope source recovery.
-- Source: READ-ONLY pg_get_functiondef / pg_proc.proacl on live Noel, 2026-11-05.
-- NOT for migration or release. Install only on disposable fresh PG17, to
-- reconcile missing source in the retained schema-only RiverSong clone.
-- The live proposer uses canonical root Ledger authority, not an extra
-- legacy organization-membership requirement. Worker acceptance is separate.
-- No fake roles, bypasses, fabricated approvals, source rows, or work writers.
DO $preflight$
BEGIN
 IF to_regprocedure('atlas.propose_native_ledger_standing_scope_owner_self_api_v1(uuid,uuid,uuid,uuid,text,text,text,timestamptz)') IS NOT NULL
    OR to_regprocedure('atlas.respond_native_ledger_standing_scope_self_api_v1(uuid,text)') IS NOT NULL THEN
  RAISE EXCEPTION 'STOP: private native standing source already present, do not replace';
 END IF;
 IF to_regprocedure('atlas.company_work_native_ledger_owner_self_v1(uuid,uuid)') IS NULL
    OR to_regprocedure('atlas.person_has_native_ledger_connection_v1(uuid,uuid,uuid)') IS NULL
    OR to_regprocedure('atlas.current_person_id_v1()') IS NULL THEN
  RAISE EXCEPTION 'STOP: governing native Person/Ledger source is not available';
 END IF;
END;$preflight$;

CREATE OR REPLACE FUNCTION atlas.propose_native_ledger_standing_scope_owner_self_api_v1(p_organization_id uuid, p_ledger_id uuid, p_worker_person_id uuid, p_organization_unit_id uuid, p_coverage_mode text, p_operation_class text, p_terms text, p_valid_until timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_owner uuid;
 v_owner_membership uuid;
 v_scope atlas.company_work_standing_assignment_scopes%ROWTYPE;
 v_terms text:=nullif(btrim(coalesce(p_terms,'')),'');
 v_class text:=nullif(btrim(coalesce(p_operation_class,'')),'');
 v_mode text:=lower(btrim(coalesce(p_coverage_mode,'')));
BEGIN
 IF auth.uid() IS NULL OR p_worker_person_id IS NULL OR
    (v_mode IS NULL OR v_mode NOT IN ('operation_class','ledger_all_work')) OR
    (v_mode='operation_class' AND (p_organization_unit_id IS NULL OR
       v_class IS NULL OR length(v_class) NOT BETWEEN 2 AND 120)) OR
    (v_mode='ledger_all_work' AND (p_organization_unit_id IS NOT NULL OR v_class IS NOT NULL)) OR
    v_terms IS NULL OR
    length(v_terms) NOT BETWEEN 30 AND 3000 OR
    (p_valid_until IS NOT NULL AND p_valid_until<=now()) THEN
   RAISE EXCEPTION 'A canonical Person, operating unit, bounded terms and valid expiry are required'
      USING ERRCODE='22023';
 END IF;
 v_owner:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
 IF v_owner=p_worker_person_id THEN
   RAISE EXCEPTION 'Owner self-work uses a separate authorized path' USING ERRCODE='23514';
 END IF;
 -- company_work_native_ledger_owner_self_v1 already enforces actual
 -- signed Principal and root-governing authority over the exact Ledger.
 -- No Organization Membership or employment category can add authority.
 v_owner_membership:=NULL;
 IF NOT atlas.person_has_native_ledger_connection_v1(
     p_organization_id,p_ledger_id,p_worker_person_id) THEN
   RAISE EXCEPTION 'Active exact native Ledger Person connection required' USING ERRCODE='23514';
 END IF;
 IF v_mode='operation_class' AND NOT EXISTS(SELECT 1 FROM atlas.organization_units u
     WHERE u.id=p_organization_unit_id AND u.organization_id=p_organization_id
       AND u.status='active') THEN
   RAISE EXCEPTION 'Active exact organization unit required' USING ERRCODE='23514';
 END IF;
 -- One recorded operation class, not unrelated Work in the same unit.
 IF v_mode='operation_class' AND NOT EXISTS(SELECT 1 FROM atlas.work_items work
   WHERE work.organization_id=p_organization_id
     AND work.organization_unit_id=p_organization_unit_id
     AND work.operation_class=v_class) THEN
   RAISE EXCEPTION 'Standing responsibility class must exist in this operating unit'
     USING ERRCODE='23514';
 END IF;
 IF EXISTS(SELECT 1 FROM atlas.company_work_standing_assignment_scopes s
     WHERE s.organization_id=p_organization_id AND s.ledger_id=p_ledger_id
       AND s.worker_person_id=p_worker_person_id
       AND s.organization_unit_id IS NOT DISTINCT FROM p_organization_unit_id
       AND s.covered_operation_class IS NOT DISTINCT FROM v_class
       AND s.coverage_mode=v_mode
       AND s.scope_state IN ('proposed','active')
       AND (s.valid_until IS NULL OR s.valid_until>now())) THEN
   RAISE EXCEPTION 'A standing scope already exists for this exact Person and unit'
       USING ERRCODE='23505';
 END IF;
 INSERT INTO atlas.company_work_standing_assignment_scopes(
   organization_id,ledger_id,worker_membership_id,worker_person_id,
   position_id,position_appointment_id,organization_unit_id,
   covered_operation_class,coverage_mode,proposed_by_person_id,proposed_by_membership_id,proposal_terms,valid_until
 ) VALUES (
   p_organization_id,p_ledger_id,NULL,p_worker_person_id,
   NULL,NULL,p_organization_unit_id,
   v_class,v_mode,v_owner,v_owner_membership,v_terms,p_valid_until
 ) RETURNING * INTO v_scope;
 RETURN jsonb_build_object(
   'ok',true,'contractVersion','native_ledger_standing_scope_v1',
   'scopeId',v_scope.id,'state','proposed','organizationId',p_organization_id,
   'ledgerId',p_ledger_id,'workerPersonId',p_worker_person_id,
   'organizationUnitId',p_organization_unit_id,'operationClass',v_class,
   'coverageMode',v_mode,
   'workerConsentRecorded',false,'workAssigned',false,'employeeSeatRequired',false);
END
$function$;

CREATE OR REPLACE FUNCTION atlas.respond_native_ledger_standing_scope_self_api_v1(p_scope_id uuid, p_decision text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_self uuid:=atlas.current_person_id_v1();
 v_scope atlas.company_work_standing_assignment_scopes%ROWTYPE;
 v_decision text:=lower(btrim(coalesce(p_decision,'')));
BEGIN
 IF auth.uid() IS NULL OR v_self IS NULL OR p_scope_id IS NULL OR
    v_decision NOT IN ('accept','decline') THEN
   RAISE EXCEPTION 'Signed-in Person and exact decision required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_scope FROM atlas.company_work_standing_assignment_scopes
    WHERE id=p_scope_id FOR UPDATE;
 IF v_scope.id IS NULL OR v_scope.worker_person_id IS DISTINCT FROM v_self OR
    v_scope.scope_state<>'proposed' OR v_scope.worker_membership_id IS NOT NULL THEN
   RAISE EXCEPTION 'No available native Person standing proposal' USING ERRCODE='42501';
 END IF;
 IF v_decision='decline' THEN
   UPDATE atlas.company_work_standing_assignment_scopes
     SET scope_state='declined',declined_at=now()
     WHERE id=v_scope.id;
   RETURN jsonb_build_object('ok',true,'contractVersion','native_ledger_standing_scope_v1',
     'scopeId',v_scope.id,'state','declined','assignmentCreated',false);
 END IF;
 IF (v_scope.valid_until IS NOT NULL AND v_scope.valid_until<=now()) OR
    NOT atlas.person_has_native_ledger_connection_v1(
      v_scope.organization_id,v_scope.ledger_id,v_self) THEN
   RAISE EXCEPTION 'Original Ledger connection or proposal is no longer effective'
     USING ERRCODE='23514';
 END IF;
 UPDATE atlas.company_work_standing_assignment_scopes SET
   scope_state='active',accepted_at=now(),accepted_by_person_id=v_self
   WHERE id=v_scope.id;
 RETURN jsonb_build_object('ok',true,'contractVersion','native_ledger_standing_scope_v1',
   'scopeId',v_scope.id,'state','active','personConsentRecorded',true,
   'assignmentCreated',false,'employeeSeatRequired',false);
END
$function$;

REVOKE ALL ON FUNCTION atlas.propose_native_ledger_standing_scope_owner_self_api_v1(uuid,uuid,uuid,uuid,text,text,text,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION atlas.respond_native_ledger_standing_scope_self_api_v1(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION atlas.propose_native_ledger_standing_scope_owner_self_api_v1(uuid,uuid,uuid,uuid,text,text,text,timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.respond_native_ledger_standing_scope_self_api_v1(uuid,text) TO authenticated;
DO $source_exact$
BEGIN
 IF NOT has_function_privilege('authenticated','atlas.propose_native_ledger_standing_scope_owner_self_api_v1(uuid,uuid,uuid,uuid,text,text,text,timestamptz)','EXECUTE')
    OR NOT has_function_privilege('authenticated','atlas.respond_native_ledger_standing_scope_self_api_v1(uuid,text)','EXECUTE')
    OR has_function_privilege('anon','atlas.propose_native_ledger_standing_scope_owner_self_api_v1(uuid,uuid,uuid,uuid,text,text,text,timestamptz)','EXECUTE')
    OR has_function_privilege('anon','atlas.respond_native_ledger_standing_scope_self_api_v1(uuid,text)','EXECUTE')
    OR NOT (SELECT prosecdef FROM pg_proc WHERE oid='atlas.propose_native_ledger_standing_scope_owner_self_api_v1(uuid,uuid,uuid,uuid,text,text,text,timestamptz)'::regprocedure)
    OR NOT (SELECT prosecdef FROM pg_proc WHERE oid='atlas.respond_native_ledger_standing_scope_self_api_v1(uuid,text)'::regprocedure)
    OR position('v_owner_membership:=NULL' in
      (SELECT prosrc FROM pg_proc WHERE oid='atlas.propose_native_ledger_standing_scope_owner_self_api_v1(uuid,uuid,uuid,uuid,text,text,text,timestamptz)'::regprocedure))=0
 THEN RAISE EXCEPTION 'STOP: recovered scope authority mismatches live contract';
 END IF;
 RAISE NOTICE 'PASS live source-only signed principal proposer and separate receiver acceptance';
END;$source_exact$;
