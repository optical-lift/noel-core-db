-- Read-only source custody postconditions for disposable clone.
DO $verify_governor_work_transfer$
DECLARE
  v_internal oid:=to_regprocedure('atlas.owner_transfer_existing_work_under_native_scope_self_api_v1(uuid,uuid,uuid,text)');
  v_public oid:=to_regprocedure('public.owner_transfer_existing_work_under_native_scope_self_api_v1(uuid,uuid,uuid,text)');
  v_definition text;
BEGIN
  IF v_internal IS NULL OR v_public IS NULL THEN
    RAISE EXCEPTION 'Canonical Work governed transfer source absent';
  END IF;
  IF has_function_privilege('anon',v_internal,'EXECUTE')
    OR has_function_privilege('anon',v_public,'EXECUTE') THEN
    RAISE EXCEPTION 'Anonymous must not be able to invoke Work transfer';
  END IF;
  IF NOT has_function_privilege('authenticated',v_internal,'EXECUTE')
    OR NOT has_function_privilege('authenticated',v_public,'EXECUTE') THEN
    RAISE EXCEPTION 'Signed native Ledger governor must be able to reach source';
  END IF;
  SELECT pg_get_functiondef(v_internal) INTO v_definition;
  IF position('company_work_native_ledger_owner_self_v1' IN v_definition)=0
    OR position('person_has_native_ledger_connection_v1' IN v_definition)=0
    OR position('company_work_native_ledger_relevance' IN v_definition)=0
    OR position('assign_native_ledger_company_work_under_scope_owner_self_api_v1' IN v_definition)=0
    OR position('accepted_by_person_id' IN v_definition)=0
    OR position('p_expected_prior_allocation_id' IN v_definition)=0
    OR position('previousResponsibilityPreservedAsHistory' IN v_definition)=0
  THEN
    RAISE EXCEPTION 'Governor scope, preserved original, or receipt validation absent';
  END IF;
  IF position('organization_memberships' IN v_definition)>0
    OR position('farm_memberships' IN v_definition)>0
    OR position('employee_seats' IN v_definition)>0 THEN
    RAISE EXCEPTION 'Work transfer must never derive authorization from legacy membership';
  END IF;
END
$verify_governor_work_transfer$;
-- SIGNED, disposable clone only. This uses four actual fixture Auth sessions,
-- current signed canonical Person bindings and actual native Ledger seats.
-- A PostgreSQL authenticated role plus exact JWT session claims exercises the
-- same security-definer API path, never a live User or production dataset.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
  '{"sub":"e5200000-0000-4000-8000-000000000001","role":"authenticated","session_id":"e5200000-0000-4000-8000-000000000011"}',true);
SELECT set_config('request.jwt.claim.sub',
  'e5200000-0000-4000-8000-000000000001',true);

DO $signed_original_work_transfer$
DECLARE
 v_prior jsonb;
 v_receipt jsonb;
 v_prior_id uuid;
 v_work uuid:='e5200000-0000-4000-8000-000000000901';
 v_owner text:='{"sub":"e5200000-0000-4000-8000-000000000001","role":"authenticated","session_id":"e5200000-0000-4000-8000-000000000011"}';
 v_worker text:='{"sub":"e5200000-0000-4000-8000-000000000002","role":"authenticated","session_id":"e5200000-0000-4000-8000-000000000012"}';
 v_outsider text:='{"sub":"e5200000-0000-4000-8000-000000000003","role":"authenticated","session_id":"e5200000-0000-4000-8000-000000000013"}';
BEGIN
 -- Prior Work responsibility exists under ANOTHER independently consented
 -- native Person scope, proving transfer does not create a replacement Work.
 v_prior:=atlas.assign_native_ledger_company_work_under_scope_owner_self_api_v1(
   v_work,'e5200000-0000-4000-8000-000000000a02',
   'Source-verified synthetic original Work assigned to the first actual signed recipient.');
 IF v_prior->>'state'<>'assigned'
   OR v_prior->>'responsiblePersonId'<>'e5200000-0000-4000-8000-000000000104'
   OR v_prior->>'newWorkCreated'<>'false' THEN
   RAISE EXCEPTION 'Initial signed original responsibility setup failed: %',v_prior;
 END IF;
 v_prior_id:=(v_prior->>'allocationId')::uuid;

 -- A recipient's membership of the same Ledger NEVER means governor authority.
 PERFORM set_config('request.jwt.claims',v_worker,true);
 PERFORM set_config('request.jwt.claim.sub','e5200000-0000-4000-8000-000000000002',true);
 BEGIN
   PERFORM public.owner_transfer_existing_work_under_native_scope_self_api_v1(
     v_work,'e5200000-0000-4000-8000-000000000a01',v_prior_id,
     'Illicit connected worker attempt to overwrite an original Work responsibility.');
   RAISE EXCEPTION 'Worker illegally transferred governor-owned original Work';
 EXCEPTION WHEN SQLSTATE '42501' OR SQLSTATE '23514' THEN NULL;
 END;

 -- A Person connected to ANOTHER Ledger cannot transfer original Work here.
 PERFORM set_config('request.jwt.claims',v_outsider,true);
 PERFORM set_config('request.jwt.claim.sub','e5200000-0000-4000-8000-000000000003',true);
 BEGIN
   PERFORM public.owner_transfer_existing_work_under_native_scope_self_api_v1(
     v_work,'e5200000-0000-4000-8000-000000000a01',v_prior_id,
     'Illicit outsider request for Work belonging to the wrong native Ledger.');
   RAISE EXCEPTION 'Cross-Ledger outsider illegally transferred original Work';
 EXCEPTION WHEN SQLSTATE '42501' OR SQLSTATE '23514' THEN NULL;
 END;

 PERFORM set_config('request.jwt.claims',v_owner,true);
 PERFORM set_config('request.jwt.claim.sub','e5200000-0000-4000-8000-000000000001',true);

 -- Even a valid governor cannot move Work under an unrelated Ledger scope.
 BEGIN
   PERFORM public.owner_transfer_existing_work_under_native_scope_self_api_v1(
     v_work,'e5200000-0000-4000-8000-000000000a03',v_prior_id,
     'Illicit wrong-Ledger recipient scope cannot govern this original Work.');
   RAISE EXCEPTION 'Wrong-Ledger governor scope admitted unrelated Work';
 EXCEPTION WHEN SQLSTATE '42501' OR SQLSTATE '23514' THEN NULL;
 END;

 -- Exact old allocation is required; a different UUID can never alter Work.
 BEGIN
   PERFORM public.owner_transfer_existing_work_under_native_scope_self_api_v1(
     v_work,'e5200000-0000-4000-8000-000000000a01',
     'e5200000-0000-4000-8000-000000000fff',
     'Illicit stale allocation request should be denied without a data change.');
   RAISE EXCEPTION 'Stale responsibility transfer failed to deny';
 EXCEPTION WHEN SQLSTATE '42501' OR SQLSTATE '23514' THEN NULL;
 END;

 -- Valid signed rooted governor, correct original Work, exact accepted receiver.
 v_receipt:=public.owner_transfer_existing_work_under_native_scope_self_api_v1(
   v_work,'e5200000-0000-4000-8000-000000000a01',v_prior_id,
   'Current root governor transfers this exact original Work to the receiving Person under real consent.');
 IF v_receipt->>'state'<>'transferred'
   OR v_receipt->>'workItemId'<>v_work::text
   OR v_receipt->>'priorAllocationId'<>v_prior_id::text
   OR v_receipt->>'responsiblePersonId'<>'e5200000-0000-4000-8000-000000000102'
   OR v_receipt->>'originalWorkIdentityPreserved'<>'true'
   OR v_receipt->>'previousResponsibilityPreservedAsHistory'<>'true'
   OR v_receipt->>'newWorkCreated'<>'false'
 THEN
   RAISE EXCEPTION 'Signed root transfer receipt failed: %',v_receipt;
 END IF;

 -- Repeated request with the previous allocation must not create another.
 BEGIN
   PERFORM public.owner_transfer_existing_work_under_native_scope_self_api_v1(
     v_work,'e5200000-0000-4000-8000-000000000a01',v_prior_id,
     'Replay should never turn one original task into two active responsibilities.');
   RAISE EXCEPTION 'Replay created an invalid duplicate responsibility';
 EXCEPTION WHEN SQLSTATE '42501' OR SQLSTATE '23514' THEN NULL;
 END;
END
$signed_original_work_transfer$;
RESET ROLE;

-- Explicit post-write source readback inside the same disposable transaction.
DO $signed_original_work_transfer_readback$
DECLARE
 v_work uuid:='e5200000-0000-4000-8000-000000000901';
BEGIN
 IF (SELECT count(*) FROM atlas.work_allocations
    WHERE work_item_id=v_work AND allocation_role='responsible' AND state='active')<>1
    OR (SELECT count(*) FROM atlas.work_allocations
      WHERE work_item_id=v_work AND allocation_role='responsible' AND state='released')<>1
    OR NOT EXISTS(SELECT 1 FROM atlas.work_allocations a
      WHERE a.work_item_id=v_work AND a.state='released'
        AND a.released_at IS NOT NULL)
    OR NOT EXISTS(SELECT 1 FROM atlas.work_allocations a
      WHERE a.work_item_id=v_work AND a.state='active'
        AND a.assignee_canonical_person_id='e5200000-0000-4000-8000-000000000102')
    OR NOT EXISTS(SELECT 1 FROM atlas.work_items w
      WHERE w.id=v_work AND w.work_state='open')
    OR (SELECT count(*) FROM atlas.work_items
      WHERE id=v_work)<>1
 THEN
   RAISE EXCEPTION 'Original Work, current Person and historical allocation did not reconcile';
 END IF;
END
$signed_original_work_transfer_readback$;

-- Only test effects are discarded; this is a disposable local clone.
ROLLBACK;
