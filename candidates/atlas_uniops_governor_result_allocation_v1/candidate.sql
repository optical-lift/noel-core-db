-- HELD source candidate ONLY; generated source/release separately governed.
-- Current production-shaped owner projection snapshot md5: 302be9714957f5bf76d665092c9609b1.
-- No source data, Work, permission, grant or application mutation intended.
-- Fail closed if the owning function differs from the audited read-only source.
DO $uniops_source_gate$
BEGIN
 IF (SELECT md5(pg_get_functiondef(p.oid)) FROM pg_proc p
     JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='atlas'
       AND p.proname='company_work_accountability_native_ledger_self_api_v1')
    IS DISTINCT FROM '302be9714957f5bf76d665092c9609b1' THEN
    RAISE EXCEPTION 'Owner projection source changed; review required' USING ERRCODE='22023';
 END IF;
END;
$uniops_source_gate$;

CREATE OR REPLACE FUNCTION atlas.company_work_accountability_native_ledger_self_api_v1(p_organization_id uuid, p_ledger_id uuid, p_scope text DEFAULT 'native_ledger'::text, p_limit integer DEFAULT 200, p_after_work_item_id uuid DEFAULT NULL::uuid)
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
         max(x.work_item_id::text)::uuid
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
           'assigneeInstitutionalPersonRecordId',
              coalesce(wa.assignee_institutional_person_record_id,
                       om_assignee.institutional_person_record_id),
           'assigneePersonId',coalesce(wa.assignee_canonical_person_id,ipr.person_id,om_assignee.person_id),
           'personProvenance',CASE
             WHEN wa.assignee_canonical_person_id IS NOT NULL
               THEN 'person_native_ledger_connection_receiver_uptake'
             WHEN wa.assignee_institutional_person_record_id IS NOT NULL
               THEN 'exact_allocation_institutional_person'
             WHEN om_assignee.institutional_person_record_id IS NOT NULL
               THEN 'active_allocation_to_membership_institutional_person'
             WHEN om_assignee.person_id IS NOT NULL
               THEN 'active_allocation_to_membership_person'
             ELSE 'no_source_person_resolution'
           END,
           'offeredResponsibilityCount',offers.offered_count
        ),
        'lastResponsibleAllocation',CASE WHEN wa_hist.id IS NULL THEN NULL ELSE
          jsonb_build_object(
            'allocationId',wa_hist.id,
            'allocationState',wa_hist.state,
            'establishmentBasisKind',wa_hist.establishment_basis_kind,
            'assigneeMembershipId',wa_hist.assignee_membership_id,
            'assigneeInstitutionalPersonRecordId',
               coalesce(wa_hist.assignee_institutional_person_record_id,
                        om_hist.institutional_person_record_id),
            'assigneePersonId',coalesce(wa_hist.assignee_canonical_person_id,ipr_hist.person_id,om_hist.person_id),
            'allocatedAt',wa_hist.allocated_at,
            'completedAt',wa_hist.completed_at,
            'releasedAt',wa_hist.released_at,
            'historicalNotCurrent',true
          ) END,
        'lastExecutionPlan',CASE WHEN ep_hist.id IS NULL THEN NULL ELSE
          jsonb_build_object(
            'planId',ep_hist.id,
            'planState',ep_hist.plan_state,
            'firstPlannedServiceDate',ep_hist.first_planned_service_date,
            'plannedServiceDate',ep_hist.planned_service_date,
            'exposureServiceDate',ep_hist.exposure_service_date,
            'rolloverCount',ep_hist.rollover_count,
            'historicalNotCurrent',true
          ) END,
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
            'decisionAt',ra.accepted_at,
            'reportsSharingLatestTimestamp',lr.timestamp_tie_count,
            'exactOrderWithinTimestampProven',lr.timestamp_tie_count=1,
            -- Source-linked report responsibility. Never substitute the most
            -- recent historical allocation or advertise it as current.
            'reportAllocation',CASE
              WHEN report_allocation.id IS NOT NULL
               AND report_allocation.assignee_canonical_person_id IS NOT NULL
               AND report_allocation.allocated_at IS NOT NULL
               AND lr.reported_at>=report_allocation.allocated_at
              THEN jsonb_build_object(
                'sourceResultId',lr.id,
                'allocationId',report_allocation.id,
                'assigneeCanonicalPersonId',report_allocation.assignee_canonical_person_id,
                'allocationState',report_allocation.state,
                'historicalNotCurrent',report_allocation.state<>'active',
                'sameOriginalAndOrganizationProven',true
              ) ELSE NULL END
          ) END,
        'latestAcceptedResult',CASE WHEN ar.id IS NULL THEN NULL ELSE
          jsonb_build_object(
            'resultId',ar.id,'resultKind',ar.result_kind,
            'reportedAt',ar.reported_at,
            'decision',ar.decision,'acceptedAt',ar.accepted_at,
            'acceptanceKind',ar.acceptance_kind
          ) END,
        'reportedResultCount',reports.total_count,
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
              rel.evidence_kind in ('owner_attested','participant_attested')
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
             a.assignee_canonical_person_id,a.assignee_institutional_person_record_id
      FROM atlas.work_allocations a
      WHERE a.organization_id=w.organization_id
        AND a.work_item_id=w.id
        AND a.allocation_role='responsible' AND a.state='active'
      ORDER BY a.allocated_at DESC,a.id DESC LIMIT 1
    ) wa ON true
    LEFT JOIN atlas.organization_memberships om_assignee
      ON om_assignee.id=wa.assignee_membership_id
     AND om_assignee.organization_id=w.organization_id
    LEFT JOIN atlas.institutional_person_records ipr
      ON ipr.id=coalesce(wa.assignee_institutional_person_record_id,
                         om_assignee.institutional_person_record_id)
     AND ipr.organization_id=w.organization_id
    -- Preserve the latest non-active responsible allocation as provenance:
    -- never advertise completed or released responsibility as current.
    LEFT JOIN LATERAL (
      SELECT a.id,a.state,a.establishment_basis_kind,a.assignee_membership_id,
             a.assignee_canonical_person_id,a.assignee_institutional_person_record_id,
             a.allocated_at,a.completed_at,a.released_at
      FROM atlas.work_allocations a
      WHERE a.organization_id=w.organization_id
        AND a.work_item_id=w.id
        AND a.allocation_role='responsible' AND a.state IN ('completed','released')
      ORDER BY a.allocated_at DESC,a.id DESC LIMIT 1
    ) wa_hist ON true
    LEFT JOIN atlas.organization_memberships om_hist
      ON om_hist.id=wa_hist.assignee_membership_id
     AND om_hist.organization_id=w.organization_id
    LEFT JOIN atlas.institutional_person_records ipr_hist
      ON ipr_hist.id=coalesce(wa_hist.assignee_institutional_person_record_id,
                            om_hist.institutional_person_record_id)
     AND ipr_hist.organization_id=w.organization_id
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
      SELECT p.id,p.plan_state,p.planned_service_date,
             p.first_planned_service_date,p.exposure_service_date,p.rollover_count
      FROM atlas.work_execution_plans p
      WHERE p.organization_id=w.organization_id AND p.work_item_id=w.id
        AND p.plan_state IN ('completed','withdrawn')
      ORDER BY p.updated_at DESC,p.id DESC LIMIT 1
    ) ep_hist ON true
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
            AND p.delivery_payload->>'managerPlanId'=ep.id::text
            AND p.delivery_payload->>'source'='company_work_employee_plan_projection_v1'
            AND p.delivery_payload->>'canonicalCompanyWorkProjection'='true'
        )::integer AS canonical_count
      FROM atlas.worker_week_projection_sources s
      JOIN atlas.worker_week_projection p ON p.id=s.projection_id
      WHERE s.work_item_id=w.id AND s.source_role='required'
        AND p.organization_id=w.organization_id
        AND wa.id IS NOT NULL
        AND p.organization_membership_id=wa.assignee_membership_id
    ) wp ON true
    LEFT JOIN LATERAL (
      SELECT r.id,r.result_kind,r.reported_at,r.responsible_allocation_id,
             r.reported_by_institutional_person_record_id,
             (SELECT count(*)::integer FROM atlas.work_execution_results tied
              WHERE tied.organization_id=r.organization_id
                AND tied.work_item_id=r.work_item_id
                AND tied.reported_at=r.reported_at) AS timestamp_tie_count
      FROM atlas.work_execution_results r
      WHERE r.organization_id=w.organization_id AND r.work_item_id=w.id
      -- A transaction timestamp may tie across multiple worker reports;
      -- UUID sorting is deterministic, never proof of report chronology.
      ORDER BY r.reported_at DESC,r.id DESC LIMIT 1
    ) lr ON true
    -- Never infer the worker from current allocation or history sorting.
    -- The Result's exact FK is independently scoped to this original.
    LEFT JOIN atlas.work_allocations report_allocation
      ON report_allocation.id=lr.responsible_allocation_id
     AND report_allocation.organization_id=w.organization_id
     AND report_allocation.work_item_id=w.id
     AND report_allocation.allocation_role='responsible'
     AND report_allocation.state IN ('active','completed','released')
    LEFT JOIN atlas.work_result_acceptances ra
      ON ra.execution_result_id=lr.id
     AND ra.organization_id=w.organization_id
     AND ra.work_item_id=w.id
    LEFT JOIN LATERAL (
      SELECT count(*)::integer AS total_count
      FROM atlas.work_execution_results r
      WHERE r.organization_id=w.organization_id AND r.work_item_id=w.id
    ) reports ON true
    LEFT JOIN LATERAL (
      SELECT r.id,r.result_kind,r.reported_at,a.decision,
             a.accepted_at,a.acceptance_kind
      FROM atlas.work_result_acceptances a
      JOIN atlas.work_execution_results r ON r.id=a.execution_result_id
       AND r.organization_id=a.organization_id
       AND r.work_item_id=a.work_item_id
      WHERE a.organization_id=w.organization_id
        AND a.work_item_id=w.id AND a.decision='accepted'
      ORDER BY a.accepted_at DESC,a.id DESC LIMIT 1
    ) ar ON true
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
        AND (rel.evidence_kind in ('owner_attested','participant_attested')
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
