-- HOLD / NOT A DEPLOYABLE RELEASE — Noel #2255, Atlas #437 / #442.
-- Exact signature replacement of the LIVE source function as of 2026-10-26.
-- Existing public RPC wrapper is unchanged and remains independently reachable.
-- Covers the old My Work list bypass without inventing a second task engine.
-- May withhold legitimate worker instructions; a safe per-original-Work,
-- per-field details source and signed POSITIVE experience tests must precede
-- any release. Work titles themselves require governor-approved disclosure.
-- Requires together: alternate Event/Today/legacy farm API closure, clone,
-- independently signed owner/participant/outsider/revoked acceptance, rollback.
-- NEVER run this directly against production. No grants, Work edits or data writes.
BEGIN;

CREATE OR REPLACE FUNCTION atlas.connected_person_my_work_self_api_v1(p_limit integer DEFAULT 50, p_after_allocation_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_self uuid := atlas.current_person_id_v1();
  v_session_access jsonb;
  v_items jsonb := '[]'::jsonb;
  v_more boolean := false;
  v_next uuid := NULL;
BEGIN
  IF auth.uid() IS NULL OR v_self IS NULL THEN
    RAISE EXCEPTION 'Signed-in canonical Person required' USING errcode='42501';
  END IF;
  -- Hold: verify active GoTrue session on each read, not a long-lived stale JWT.
  v_session_access := atlas.reality_access_self_api_v1();
  IF v_session_access->>'state' IS DISTINCT FROM 'ready'
     OR v_session_access->>'authenticated' IS DISTINCT FROM 'true'
     OR v_session_access->'person'->>'id' IS DISTINCT FROM v_self::text
  THEN
    RAISE EXCEPTION 'Source authorization unavailable' USING errcode='42501';
  END IF;
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'Limit must be between 1 and 100' USING errcode='22023';
  END IF;

  WITH eligible AS MATERIALIZED (
    SELECT
      a.id allocation_id,w.id work_id,w.organization_id,
      (a.establishment_basis->>'nativeLedgerId')::uuid ledger_id,
      -- A Work allocation is not a grant to disclose arbitrary source details.
      -- Keep response field shape for the existing Atlas My Work client,
      -- but withhold instructions until an exact source-owned field decision.
      w.title,
      CASE WHEN atlas.connected_person_work_field_currently_approved_v1(
        (a.establishment_basis->>'nativeLedgerId')::uuid,w.id,v_self,
        'instructions') THEN w.instructions ELSE NULL::text END AS instructions,
      w.result_contract_key,
      a.establishment_basis_kind,a.allocated_at,
      plan.id plan_id,plan.plan_state,
      plan.planned_service_date,plan.exposure_service_date,
      coalesce(plan_counts.current_plan_count,0) current_plan_count,
      coalesce(relevance.has_relevance,false) has_relevance
    FROM atlas.work_allocations a
    JOIN atlas.work_items w ON w.id=a.work_item_id
      AND w.organization_id=a.organization_id
    LEFT JOIN LATERAL (
      SELECT p.id,p.plan_state,p.planned_service_date,p.exposure_service_date
      FROM atlas.work_execution_plans p
      WHERE p.work_item_id=w.id AND p.organization_id=w.organization_id
        AND p.responsible_allocation_id=a.id
        AND p.plan_state IN ('active','needs_replan')
      ORDER BY CASE WHEN p.plan_state='active' THEN 0 ELSE 1 END,
        p.updated_at DESC,p.id DESC LIMIT 1
    ) plan ON true
    LEFT JOIN LATERAL (
      SELECT count(*)::integer current_plan_count
      FROM atlas.work_execution_plans p
      WHERE p.work_item_id=w.id AND p.organization_id=w.organization_id
        AND p.plan_state IN ('active','needs_replan')
    ) plan_counts ON true
    LEFT JOIN LATERAL (
      SELECT EXISTS (
        SELECT 1 FROM atlas.company_work_native_ledger_relevance x
        WHERE x.work_item_id=w.id AND x.organization_id=w.organization_id
          AND x.ledger_id=(a.establishment_basis->>'nativeLedgerId')::uuid
          AND x.attribution_state='active'
          AND (
            x.evidence_kind IN ('owner_attested','participant_attested')
            OR (x.evidence_kind='source_verified' AND EXISTS (
              SELECT 1
              FROM atlas.company_work_native_ledger_exact_source_v1(
                x.work_item_id,x.ledger_id
              ) verified
              WHERE verified.source_schema=x.source_schema
                AND verified.source_table=x.source_table
                AND verified.source_id=x.source_id
            ))
          )
      ) has_relevance
    ) relevance ON true
    WHERE a.allocation_role='responsible' AND a.state='active'
      AND a.assignee_canonical_person_id=v_self
      AND a.assignee_membership_id IS NULL
      AND a.establishment_basis_kind IN (
        'person_connection_receiver_uptake','delegated_under_standing_scope',
        'ledger_connection_direct_assignment'
      )
      AND w.work_state='open'
      AND (p_after_allocation_id IS NULL OR a.id>p_after_allocation_id)
      AND atlas.person_has_native_ledger_connection_v1(
        w.organization_id,(a.establishment_basis->>'nativeLedgerId')::uuid,v_self
      )
      -- Critical: source relevance must FILTER rows; the old implementation
      -- only returned relevance as a flag alongside disclosable fields.
      AND relevance.has_relevance IS TRUE
      AND atlas.connected_person_work_field_currently_approved_v1(
        (a.establishment_basis->>'nativeLedgerId')::uuid,w.id,v_self,'title')
    ORDER BY a.id
    LIMIT p_limit+1
  ), numbered AS (
    SELECT e.*,row_number() OVER (ORDER BY e.allocation_id) rn
    FROM eligible e
  )
  SELECT
    coalesce(jsonb_agg(
      jsonb_build_object(
        'workItemId',r.work_id,'allocationId',r.allocation_id,
        'organizationId',r.organization_id,'ledgerId',r.ledger_id,
        'title',r.title,'instructions',r.instructions,
        'resultContractKey',r.result_contract_key,
        'establishmentBasisKind',r.establishment_basis_kind,
        'allocatedAt',r.allocated_at,'planId',r.plan_id,
        'planState',r.plan_state,'workOn',r.planned_service_date,
        'exposureDate',r.exposure_service_date,
        'workRelevanceVerified',r.has_relevance,
        'canPlace',r.has_relevance AND r.current_plan_count<=1,
        'scheduleState',CASE
          WHEN r.current_plan_count>1 THEN 'conflict'
          WHEN r.plan_id IS NULL AND r.current_plan_count>0 THEN 'unverified_plan'
          WHEN r.plan_id IS NULL THEN 'unscheduled'
          WHEN r.plan_state='needs_replan' THEN 'needs_replan'
          WHEN r.plan_state='active' AND
            r.planned_service_date IS NOT NULL AND
            r.exposure_service_date IS NOT NULL THEN 'scheduled'
          ELSE 'unverified_plan'
        END
      ) ORDER BY r.allocation_id
    ) FILTER(WHERE r.rn<=p_limit),'[]'::jsonb),
    count(*)>p_limit,
    (array_agg(r.allocation_id ORDER BY r.rn) FILTER (WHERE r.rn=p_limit))[1]
  INTO v_items,v_more,v_next
  FROM numbered r;

  RETURN jsonb_build_object(
    'ok',true,'contractVersion','connected_person_my_work_v1',
    'personId',v_self,'items',v_items,
    'hasMore',v_more,'nextAllocationId',CASE WHEN v_more THEN v_next ELSE NULL END,
    'sourceScope','active_responsible_person_native_ledger_work',
    'scheduleReadAcrossAllDates',true,
    'optionalRequestsExcluded',true,'noPersonalTaskCreated',true
  );
END
$function$
;
COMMIT;
