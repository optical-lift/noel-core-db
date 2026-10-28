-- DRAFT / NOT DEPLOYED. Generic canonical Person responsibility continuity.
-- Preserve the original Work item and old membership allocation as history.
-- This is not a legacy farm task reader, import engine, or grant of new authority.
--
-- Only an already-accepted native Ledger standing scope for the SAME canonical
-- Person as the currently responsible institutional membership can be used.
-- The actual rooted governor must invoke this through an authenticated session.
CREATE OR REPLACE FUNCTION atlas.owner_continue_membership_work_as_person_under_scope_self_api_v1(
  p_work_item_id uuid,
  p_scope_id uuid,
  p_expected_allocation_id uuid,
  p_reason text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_work atlas.work_items%ROWTYPE;
  v_scope atlas.company_work_standing_assignment_scopes%ROWTYPE;
  v_prior atlas.work_allocations%ROWTYPE;
  v_old_member atlas.organization_memberships%ROWTYPE;
  v_owner uuid;
  v_reason text := nullif(btrim(coalesce(p_reason,'')),'');
  v_new jsonb;
BEGIN
  IF auth.uid() IS NULL
    OR p_work_item_id IS NULL OR p_scope_id IS NULL
    OR p_expected_allocation_id IS NULL
    OR v_reason IS NULL OR length(v_reason) NOT BETWEEN 12 AND 1000
  THEN
    RAISE EXCEPTION 'Signed governor, exact original Work, allocation, scope and reason required'
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
    RAISE EXCEPTION 'Open exact Work with an accepted matching native Person scope required'
      USING ERRCODE='23514';
  END IF;

  v_owner:=atlas.company_work_native_ledger_owner_self_v1(
    v_work.organization_id,v_scope.ledger_id);
  IF v_scope.proposed_by_person_id IS DISTINCT FROM v_owner
    OR NOT atlas.person_has_native_ledger_connection_v1(
      v_work.organization_id,v_scope.ledger_id,v_scope.worker_person_id)
  THEN
    RAISE EXCEPTION 'Current rooted governor or recipient Ledger connection unavailable'
      USING ERRCODE='42501';
  END IF;

  -- The caller cannot use a scope as a substitute for exact Work custody.
  IF NOT EXISTS (
    SELECT 1 FROM atlas.company_work_native_ledger_relevance r
    WHERE r.work_item_id=v_work.id AND r.organization_id=v_work.organization_id
      AND r.ledger_id=v_scope.ledger_id AND r.attribution_state='active'
      AND (r.evidence_kind='owner_attested' OR
        (r.evidence_kind='source_verified' AND EXISTS (
          SELECT 1 FROM atlas.company_work_native_ledger_exact_source_v1(
            v_work.id,v_scope.ledger_id) e
          WHERE e.source_schema=r.source_schema AND e.source_table=r.source_table
            AND e.source_id=r.source_id
        )))
  ) THEN
    RAISE EXCEPTION 'Exact native Ledger relevance must be source-proven before continuity'
      USING ERRCODE='23514';
  END IF;

  -- Do not push original, differently protected Subject links through a
  -- broad Work agreement. Each Subject disclosure must be judged separately.
  -- This restricted first increment handles existing unlinked originals only.
  IF EXISTS (
    SELECT 1 FROM atlas.work_item_context_links l
    WHERE l.organization_id=v_work.organization_id AND l.work_item_id=v_work.id
  ) THEN
    RAISE EXCEPTION 'Linked Subject disclosure must be verified before continuity'
      USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_prior FROM atlas.work_allocations a
    WHERE a.id=p_expected_allocation_id AND a.work_item_id=v_work.id
      AND a.organization_id=v_work.organization_id
      AND a.allocation_role='responsible' AND a.state='active'
      AND a.assignee_membership_id IS NOT NULL
      AND a.assignee_canonical_person_id IS NULL
    FOR UPDATE;
  IF v_prior.id IS NULL
    OR (SELECT count(*) FROM atlas.work_allocations a
        WHERE a.work_item_id=v_work.id AND a.state='active'
          AND a.allocation_role='responsible')<>1
  THEN
    RAISE EXCEPTION 'Exactly one original active membership responsibility expected'
      USING ERRCODE='23514';
  END IF;
  SELECT * INTO v_old_member FROM atlas.organization_memberships m
    WHERE m.id=v_prior.assignee_membership_id AND m.organization_id=v_work.organization_id
    FOR SHARE;
  IF v_old_member.id IS NULL
    OR v_old_member.person_id IS DISTINCT FROM v_scope.worker_person_id
    OR NOT atlas.organization_membership_present_effective_at_v1(
       v_old_member.id,v_old_member.organization_id,now())
  THEN
    RAISE EXCEPTION 'Existing responsibility does not belong to the same canonical Person'
      USING ERRCODE='42501';
  END IF;

  IF EXISTS(SELECT 1 FROM atlas.company_work_initial_responsibility_offers o
     WHERE o.work_item_id=v_work.id AND o.offer_state='offered')
     OR EXISTS(SELECT 1 FROM atlas.company_work_responsibility_transfer_offers o
     WHERE o.work_item_id=v_work.id AND o.offer_state='offered')
  THEN
    RAISE EXCEPTION 'Resolve pending responsibility offers before continuity'
      USING ERRCODE='23514';
  END IF;

  -- A transactionally preserved old carrier, never an overwrite of its
  -- historical assignee or establishment provenance.
  UPDATE atlas.work_allocations
    SET state='released',
        metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
          'nativePersonContinuity','superseded_by_accepted_person_scope',
          'continuityLedgerId',v_scope.ledger_id,
          'continuityScopeId',v_scope.id,
          'continuityOriginalAllocationId',v_prior.id,
          'continuityReason',v_reason,
          'continuityAt',now())
  WHERE id=v_prior.id AND state='active';

  -- Reuse the EXISTING governing Person-native allocator, including all
  -- accepted standing scope, exact Ledger, result contract and trigger gates.
  v_new:=atlas.assign_native_ledger_company_work_under_scope_owner_self_api_v1(
    v_work.id,v_scope.id,
    'Continuity from same Person''s historical Work carrier: '||v_reason);

  IF v_new->>'state'<>'assigned'
    OR v_new->>'workItemId' IS DISTINCT FROM v_work.id::text
    OR v_new->>'responsiblePersonId' IS DISTINCT FROM v_scope.worker_person_id::text
    OR v_new->>'scopeId' IS DISTINCT FROM v_scope.id::text
  THEN
    RAISE EXCEPTION 'Canonical Person allocation receipt did not verify'
      USING ERRCODE='23514';
  END IF;

  RETURN jsonb_build_object(
    'ok',true,'contractVersion','native_ledger_person_work_continuity_v1',
    'state','continued_same_person','workItemId',v_work.id,
    'ledgerId',v_scope.ledger_id,'scopeId',v_scope.id,
    'priorAllocationId',v_prior.id,
    'newAllocationId',v_new->>'allocationId',
    'responsiblePersonId',v_scope.worker_person_id,
    'sourceWorkIdPreserved',true,
    'historicAllocationPreserved',true,
    'employeeSeatRequired',false,
    'workDayPlanned',false,
    'workerResultRecorded',false,
    'workerReadProven',false
  );
END
$function$;

REVOKE ALL ON FUNCTION atlas.owner_continue_membership_work_as_person_under_scope_self_api_v1(
 uuid,uuid,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION atlas.owner_continue_membership_work_as_person_under_scope_self_api_v1(
 uuid,uuid,uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.owner_continue_membership_work_as_person_under_scope_self_api_v1(
  p_work_item_id uuid,p_scope_id uuid,p_expected_allocation_id uuid,p_reason text
) RETURNS jsonb
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO 'pg_catalog'
AS $function$
  SELECT atlas.owner_continue_membership_work_as_person_under_scope_self_api_v1(
    p_work_item_id,p_scope_id,p_expected_allocation_id,p_reason);
$function$;
REVOKE ALL ON FUNCTION public.owner_continue_membership_work_as_person_under_scope_self_api_v1(
 uuid,uuid,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.owner_continue_membership_work_as_person_under_scope_self_api_v1(
 uuid,uuid,uuid,text) TO authenticated;
