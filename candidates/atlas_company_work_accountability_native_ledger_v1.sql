BEGIN;

-- Build 3/5: source-backed institutional accountability, not a new work or
-- worker-day writer. Exact native Ledger relevance is re-proved at read time.
CREATE OR REPLACE FUNCTION atlas.company_work_accountability_native_ledger_self_api_v1(
  p_organization_id uuid,
  p_ledger_id uuid,
  p_scope text DEFAULT 'native_ledger',
  p_limit integer DEFAULT 200,
  p_after_work_item_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_actor_person_id uuid;
  v_items jsonb := '[]'::jsonb;
  v_last_id uuid;
  v_without_proof bigint;
BEGIN
  -- Build-1 root gate proves current auth session, canonical Person/Principal,
  -- current native seat, exact Organization participation and BOTH roots.
  -- No position title, employee seat or generic membership extends this grant.
  v_actor_person_id := atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id, p_ledger_id
  );

  IF p_scope IS NULL OR p_scope NOT IN ('native_ledger','organization') THEN
    RAISE EXCEPTION 'Scope must be native_ledger or organization.' USING ERRCODE='22023';
  END IF;
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 500 THEN
    RAISE EXCEPTION 'Limit must be between 1 and 500.' USING ERRCODE='22023';
  END IF;

  SELECT COALESCE(jsonb_agg(x.item ORDER BY x.work_item_id),'[]'::jsonb),
         max(x.work_item_id)
    INTO v_items,v_last_id
  FROM (
    SELECT w.id AS work_item_id,
      jsonb_build_object(
        'workItemId',w.id,
        'organizationId',w.organization_id,
        'organizationUnitId',w.organization_unit_id,
        'title',w.title,
        'operationClass',w.operation_class,
        'workState',w.work_state,
        'sourceObjectType',w.source_object_type,
        'resultContractKey',w.result_contract_key,
        'selectedNativeLedgerId',p_ledger_id,
        'nativeLedgerRelevance',CASE WHEN w.has_exact_ledger_evidence
           THEN 'established_for_selected_ledger'
           ELSE 'not_established_for_selected_ledger' END,
        'otherLedgerEvidenceDoesNotProveExclusion',true,
        'responsibility',jsonb_build_object(
           'allocationId',wa.id,
           'state',CASE WHEN wa.id IS NULL THEN 'no_active_responsible_allocation'
                        ELSE 'active_responsible_allocation_observed' END,
           'establishmentBasisKind',wa.establishment_basis_kind,
           'assigneeMembershipId',wa.assignee_membership_id,
           'assigneeInstitutionalPersonRecordId',wa.assignee_institutional_person_record_id,
           'assigneePersonId',ipr.person_id,
           'offeredResponsibilityCount',offers.offered_count
        ),
        'planning',jsonb_build_object(
           'planId',ep.id,
           'planState',coalesce(ep.plan_state,'no_current_plan'),
           'plannedServiceDate',ep.planned_service_date,
           'firstPlannedServiceDate',ep.first_planned_service_date,
           'exposureServiceDate',ep.exposure_service_date,
           'rolloverCount',coalesce(ep.rollover_count,0),
           'sourceWindowEarliestAt',tc.earliest_lawful_at,
           'sourceWindowHardFinishAt',tc.hard_finish_at,
           'sourceWindowLatestLawfulAt',tc.latest_lawful_at,
           'planHistoryEventCount',coalesce(events.event_count,0),
           'openConflictCount',coalesce(conflicts.open_count,0)
        ),
        'workerProjection',jsonb_build_object(
           'state',CASE
             WHEN coalesce(wp.canonical_count,0)>0
               THEN 'governed_plan_projection_observed'
             WHEN coalesce(wp.related_count,0)>0
               THEN 'legacy_or_unverified_projection_observed'
             ELSE 'no_matching_worker_projection_observed' END,
           'canonicalProjectionCount',coalesce(wp.canonical_count,0),
           'otherRelatedProjectionCount',
             coalesce(wp.related_count,0)-coalesce(wp.canonical_count,0),
           'workerViewedReceipt','not_proven',
           'currentExecutionWarrant','not_proven_by_projection',
           'employeePrivateContextRead',false
        ),
        'latestWorkerReport',CASE WHEN lr.id IS NULL THEN NULL ELSE
          jsonb_build_object(
            'resultId',lr.id,'resultKind',lr.result_kind,
            'reportedAt',lr.reported_at,
            'reportedByInstitutionalPersonRecordId',lr.reported_by_institutional_person_record_id,
            'decision',coalesce(ra.decision,'no_acceptance_for_this_result'),
            'decisionAt',ra.accepted_at
          ) END,
        'acceptedResultIsDistinctFromReport',true
      ) AS item
    FROM (
      SELECT wi.*,
        EXISTS (
          SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
          WHERE rel.organization_id=wi.organization_id
            AND rel.work_item_id=wi.id
            AND rel.ledger_id=p_ledger_id
            AND rel.attribution_state='active'
            AND (
              rel.evidence_kind='owner_attested'
              OR (rel.evidence_kind='source_verified' AND EXISTS (
                SELECT 1
                FROM atlas.company_work_native_ledger_exact_source_v1(
                  rel.work_item_id,rel.ledger_id
                ) proof
                WHERE proof.source_schema=rel.source_schema
                  AND proof.source_table=rel.source_table
                  AND proof.source_id=rel.source_id
              ))
            )
        ) AS has_exact_ledger_evidence
      FROM atlas.work_items wi
      WHERE wi.organization_id=p_organization_id
        AND (p_after_work_item_id IS NULL OR wi.id>p_after_work_item_id)
      ORDER BY wi.id
    ) w
    LEFT JOIN LATERAL (
      SELECT a.id,a.establishment_basis_kind,a.assignee_membership_id,
             a.assignee_institutional_person_record_id
      FROM atlas.work_allocations a
      WHERE a.organization_id=w.organization_id
        AND a.work_item_id=w.id
        AND a.allocation_role='responsible' AND a.state='active'
      ORDER BY a.allocated_at DESC,a.id DESC LIMIT 1
    ) wa ON true
    LEFT JOIN atlas.institutional_person_records ipr
      ON ipr.id=wa.assignee_institutional_person_record_id
     AND ipr.organization_id=w.organization_id
    LEFT JOIN LATERAL (
      SELECT count(*)::integer AS offered_count
      FROM atlas.company_work_responsibility_transfer_offers o
      WHERE o.organization_id=w.organization_id
        AND o.work_item_id=w.id AND o.offer_state='offered'
    ) offers ON true
    LEFT JOIN LATERAL (
      SELECT p.id,p.plan_state,p.responsible_allocation_id,
             p.assignee_membership_id,p.planned_service_date,
             p.first_planned_service_date,p.exposure_service_date,p.rollover_count
      FROM atlas.work_execution_plans p
      WHERE p.organization_id=w.organization_id
        AND p.work_item_id=w.id AND p.plan_state IN ('active','needs_replan')
      ORDER BY p.updated_at DESC,p.id DESC LIMIT 1
    ) ep ON true
    LEFT JOIN LATERAL (
      SELECT t.earliest_lawful_at,t.hard_finish_at,t.latest_lawful_at
      FROM atlas.work_time_contracts t
      WHERE t.organization_id=w.organization_id AND t.work_item_id=w.id
        AND t.contract_state='active'
      ORDER BY t.created_at DESC,t.id DESC LIMIT 1
    ) tc ON true
    LEFT JOIN LATERAL (
      SELECT count(*)::integer AS event_count
      FROM atlas.work_execution_plan_events e
      WHERE e.organization_id=w.organization_id AND e.work_item_id=w.id
    ) events ON true
    LEFT JOIN LATERAL (
      SELECT count(*)::integer AS open_count
      FROM atlas.work_planning_conflicts c
      WHERE c.organization_id=w.organization_id AND c.work_item_id=w.id
        AND c.state='open'
    ) conflicts ON true
    LEFT JOIN LATERAL (
      SELECT count(*)::integer AS related_count,
        count(*) FILTER (
          WHERE ep.id IS NOT NULL
            AND ep.plan_state='active'
            AND ep.responsible_allocation_id=wa.id
            AND ep.assignee_membership_id=wa.assignee_membership_id
            AND p.source_kind='work_item'
            AND p.source_id=w.id
            AND p.planned_date=ep.exposure_service_date
            AND p.delivery_payload->>'projectionAuthority'='work_execution_plans'
        )::integer AS canonical_count
      FROM atlas.worker_week_projection_sources s
      JOIN atlas.worker_week_projection p ON p.id=s.projection_id
      WHERE s.work_item_id=w.id AND s.source_role='required'
        AND p.organization_id=w.organization_id
        AND wa.id IS NOT NULL
        AND p.organization_membership_id=wa.assignee_membership_id
    ) wp ON true
    LEFT JOIN LATERAL (
      SELECT r.id,r.result_kind,r.reported_at,
             r.reported_by_institutional_person_record_id
      FROM atlas.work_execution_results r
      WHERE r.organization_id=w.organization_id AND r.work_item_id=w.id
      ORDER BY r.reported_at DESC,r.id DESC LIMIT 1
    ) lr ON true
    LEFT JOIN atlas.work_result_acceptances ra
      ON ra.execution_result_id=lr.id
     AND ra.organization_id=w.organization_id
     AND ra.work_item_id=w.id
    WHERE p_scope='organization' OR w.has_exact_ledger_evidence
    ORDER BY w.id
    LIMIT p_limit
  ) x;

  -- This count is diagnostic for institution-owned work with no CURRENT
  -- native Ledger evidence at all. It does not authorize showing those
  -- Work rows in the selected native Ledger.
  SELECT count(*) INTO v_without_proof
  FROM atlas.work_items wi
  WHERE wi.organization_id=p_organization_id
    AND NOT EXISTS (
      SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
      WHERE rel.organization_id=wi.organization_id
        AND rel.work_item_id=wi.id
        AND rel.attribution_state='active'
        AND (rel.evidence_kind='owner_attested'
          OR (rel.evidence_kind='source_verified' AND EXISTS (
            SELECT 1 FROM atlas.company_work_native_ledger_exact_source_v1(
              rel.work_item_id,rel.ledger_id
            ) proof
            WHERE proof.source_schema=rel.source_schema
              AND proof.source_table=rel.source_table
              AND proof.source_id=rel.source_id
          )))
    );

  RETURN jsonb_build_object(
    'contractVersion','company_work_accountability_native_ledger_v1',
    'organizationId',p_organization_id,
    'selectedNativeLedgerId',p_ledger_id,
    'scopeMode',p_scope,
    'scopeRule',CASE WHEN p_scope='native_ledger'
      THEN 'only_currently_proven_exact_native_ledger_relevance'
      ELSE 'explicit_organization_accountability_not_ledger_attribution' END,
    'items',v_items,
    'pageLimit',p_limit,
    'nextAfterWorkItemId',v_last_id,
    'organizationWorkWithoutAnyCurrentNativeLedgerEvidenceCount',v_without_proof,
    'facts',jsonb_build_object(
      'workOwnedByOrganization',true,
      'reportIsNotAcceptance',true,
      'managerDoesNotImpersonateWorker',true,
      'projectionIsNotProofWorkerViewed',true,
      'projectionIsNotExecutionLease',true,
      'principalClockEscalationNotRequired',true,
      'privatePersonalAtlasNotRead',true,
      'noNewResponsibilityOrPlanCreated',true,
      'sortPriorityNotInvented',true
    )
  );
END
$function$;

REVOKE ALL ON FUNCTION atlas.company_work_accountability_native_ledger_self_api_v1(
  uuid,uuid,text,integer,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION atlas.company_work_accountability_native_ledger_self_api_v1(
  uuid,uuid,text,integer,uuid) TO authenticated;

COMMENT ON FUNCTION atlas.company_work_accountability_native_ledger_self_api_v1(
  uuid,uuid,text,integer,uuid)
IS 'Build 3 read-only: exact native Ledger or explicitly labeled Organization Work accountability; authenticated root owner only. Current allocation, institutional plan, actual canonical projection evidence, worker report and source result acceptance remain distinct.';

COMMIT;
