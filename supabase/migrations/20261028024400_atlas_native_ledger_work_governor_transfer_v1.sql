-- CANDIDATE ONLY / NOT PRODUCTION. Generic original Work responsibility transfer.
-- Authority is current rooted native Ledger governance PLUS a separately
-- receiver-accepted native Person scope. Historical membership does not grant
-- authority, authenticate the recipient, or establish consent.
CREATE OR REPLACE FUNCTION atlas.owner_transfer_existing_work_under_native_scope_self_api_v1(
  p_work_item_id uuid,
  p_scope_id uuid,
  p_expected_prior_allocation_id uuid,
  p_reason text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_work atlas.work_items%ROWTYPE;
  v_scope atlas.company_work_standing_assignment_scopes%ROWTYPE;
  v_prior atlas.work_allocations%ROWTYPE;
  v_owner uuid;
  v_reason text := nullif(btrim(coalesce(p_reason,'')),'');
  v_new jsonb;
BEGIN
  IF auth.uid() IS NULL OR p_work_item_id IS NULL OR p_scope_id IS NULL
    OR p_expected_prior_allocation_id IS NULL
    OR v_reason IS NULL OR length(v_reason) NOT BETWEEN 12 AND 1000
  THEN
    RAISE EXCEPTION 'Signed governor, exact Work, prior allocation, scope and reason required'
      USING ERRCODE='22023';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(
    'atlas.company_work.responsibility:'||p_work_item_id::text,0));
  SELECT * INTO v_work FROM atlas.work_items
    WHERE id=p_work_item_id AND work_state='open' FOR UPDATE;
  SELECT * INTO v_scope FROM atlas.company_work_standing_assignment_scopes
    WHERE id=p_scope_id FOR UPDATE;
  IF v_work.id IS NULL OR v_scope.id IS NULL
    OR v_scope.organization_id<>v_work.organization_id
    OR v_scope.scope_state<>'active' OR v_scope.accepted_at IS NULL
    OR v_scope.worker_membership_id IS NOT NULL
    OR v_scope.accepted_by_person_id IS DISTINCT FROM v_scope.worker_person_id
    OR (v_scope.valid_until IS NOT NULL AND v_scope.valid_until<=now())
    OR v_scope.coverage_mode NOT IN ('ledger_all_work','operation_class','exact_work')
    OR (v_scope.coverage_mode='exact_work'
       AND v_scope.covered_work_item_id IS DISTINCT FROM v_work.id)
    OR (v_scope.coverage_mode='operation_class'
       AND (v_scope.covered_operation_class IS DISTINCT FROM v_work.operation_class
         OR v_scope.organization_unit_id IS DISTINCT FROM v_work.organization_unit_id))
  THEN
    RAISE EXCEPTION 'Open Work and exact active accepted Person scope required'
      USING ERRCODE='23514';
  END IF;

  v_owner:=atlas.company_work_native_ledger_owner_self_v1(
    v_work.organization_id,v_scope.ledger_id);
  IF v_scope.proposed_by_person_id IS DISTINCT FROM v_owner
    OR NOT atlas.person_has_native_ledger_connection_v1(
       v_work.organization_id,v_scope.ledger_id,v_scope.worker_person_id)
  THEN
    RAISE EXCEPTION 'Governing owner or Person connection unavailable'
      USING ERRCODE='42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM atlas.company_work_native_ledger_relevance r
    WHERE r.work_item_id=v_work.id AND r.organization_id=v_work.organization_id
      AND r.ledger_id=v_scope.ledger_id AND r.attribution_state='active'
      AND (r.evidence_kind='owner_attested' OR
        (r.evidence_kind='source_verified' AND EXISTS (
          SELECT 1 FROM atlas.company_work_native_ledger_exact_source_v1(
            v_work.id,v_scope.ledger_id) proof
          WHERE proof.source_schema=r.source_schema
            AND proof.source_table=r.source_table
            AND proof.source_id=r.source_id)))
  ) THEN
    RAISE EXCEPTION 'Exact original Work Ledger relevance unproven'
      USING ERRCODE='23514';
  END IF;

  -- Until the governor's per-Subject disclosure proof is integrated with
  -- the transfer admission, protect all Work carrying Subject links.
  IF EXISTS (
    SELECT 1 FROM atlas.work_item_context_links l
    WHERE l.organization_id=v_work.organization_id AND l.work_item_id=v_work.id
  ) THEN
    RAISE EXCEPTION 'Linked Subjects require separate effective disclosure review'
      USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_prior FROM atlas.work_allocations a
    WHERE a.id=p_expected_prior_allocation_id AND a.work_item_id=v_work.id
      AND a.organization_id=v_work.organization_id
      AND a.allocation_role='responsible' AND a.state='active'
    FOR UPDATE;

  IF v_prior.id IS NULL OR
    (SELECT count(*) FROM atlas.work_allocations a
     WHERE a.work_item_id=v_work.id AND a.allocation_role='responsible'
       AND a.state='active')<>1 THEN
    RAISE EXCEPTION 'Exactly one matching current responsibility required'
      USING ERRCODE='23514';
  END IF;
  IF v_prior.assignee_canonical_person_id IS NOT DISTINCT FROM v_scope.worker_person_id
    AND v_prior.assignee_membership_id IS NULL THEN
    RAISE EXCEPTION 'This canonical Person already owns this Work'
      USING ERRCODE='23514';
  END IF;

  IF EXISTS(SELECT 1 FROM atlas.company_work_initial_responsibility_offers o
     WHERE o.work_item_id=v_work.id AND o.offer_state='offered')
     OR EXISTS(SELECT 1 FROM atlas.company_work_responsibility_transfer_offers o
     WHERE o.work_item_id=v_work.id AND o.offer_state='offered')
  THEN
    RAISE EXCEPTION 'Pending responsibility offers must be resolved first'
      USING ERRCODE='23514';
  END IF;

  UPDATE atlas.work_allocations
    SET state='released',
        released_at=now(),
        metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
          'transferBasis','rooted_native_ledger_governor_and_accepted_person_scope',
          'transferredToPersonId',v_scope.worker_person_id,
          'transferLedgerId',v_scope.ledger_id,
          'transferScopeId',v_scope.id,
          'transferReason',v_reason,
          'releasedByGovernorPersonId',v_owner,
          'transferredAt',now())
  WHERE id=v_prior.id AND state='active';

  -- Existing guarded source enforces the exact Person/Ledger/acceptance
  -- contract; do not build an alternative allocator or fabricate uptake.
  v_new:=atlas.assign_native_ledger_company_work_under_scope_owner_self_api_v1(
    v_work.id,v_scope.id,
    'Governor transferred original Ledger Work under accepted scope: '||v_reason);

  IF v_new->>'state'<>'assigned'
    OR v_new->>'workItemId' IS DISTINCT FROM v_work.id::text
    OR v_new->>'responsiblePersonId' IS DISTINCT FROM v_scope.worker_person_id::text
    OR v_new->>'scopeId' IS DISTINCT FROM v_scope.id::text
  THEN
    RAISE EXCEPTION 'Verified governed Person allocation receipt missing'
      USING ERRCODE='23514';
  END IF;

  RETURN jsonb_build_object(
    'ok',true,'contractVersion','native_ledger_governor_work_transfer_v1',
    'state','transferred','workItemId',v_work.id,
    'ledgerId',v_scope.ledger_id,'scopeId',v_scope.id,
    'priorAllocationId',v_prior.id,
    'newAllocationId',v_new->>'allocationId',
    'responsiblePersonId',v_scope.worker_person_id,
    'originalWorkIdentityPreserved',true,
    'previousResponsibilityPreservedAsHistory',true,
    'workerConsentRecordedByStandingScope',true,
    'newWorkCreated',false,
    'workerReadProven',false,
    'workDayScheduled',false);
END
$function$;

REVOKE ALL ON FUNCTION atlas.owner_transfer_existing_work_under_native_scope_self_api_v1(
 uuid,uuid,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION atlas.owner_transfer_existing_work_under_native_scope_self_api_v1(
 uuid,uuid,uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.owner_transfer_existing_work_under_native_scope_self_api_v1(
  p_work_item_id uuid,p_scope_id uuid,p_expected_prior_allocation_id uuid,p_reason text
) RETURNS jsonb
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO 'pg_catalog'
AS $function$
  SELECT atlas.owner_transfer_existing_work_under_native_scope_self_api_v1(
    p_work_item_id,p_scope_id,p_expected_prior_allocation_id,p_reason);
$function$;
REVOKE ALL ON FUNCTION public.owner_transfer_existing_work_under_native_scope_self_api_v1(
 uuid,uuid,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.owner_transfer_existing_work_under_native_scope_self_api_v1(
 uuid,uuid,uuid,text) TO authenticated;
