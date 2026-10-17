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
           'assigneePersonId',coalesce(ipr.person_id,om_assignee.person_id),
           'personProvenance',CASE
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
    LEFT JOIN atlas.organization_memberships om_assignee
      ON om_assignee.id=wa.assignee_membership_id
     AND om_assignee.organization_id=w.organization_id
    LEFT JOIN atlas.institutional_person_records ipr
      ON ipr.id=coalesce(wa.assignee_institutional_person_record_id,
                         om_assignee.institutional_person_record_id)
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

-- Narrow worker-self date alignment repair. Original source definitions from the
-- live schema; no manager impersonation, no relaxed RLS and no new writer.
CREATE OR REPLACE FUNCTION atlas.company_work_projection_result_reporting_self_v1(p_projection_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_uid uuid:=auth.uid();
  v_projection atlas.worker_week_projection%rowtype;
  v_farm_id uuid;
  v_context jsonb;
  v_work_ids uuid[];
  v_work atlas.work_items%rowtype;
  v_policy atlas.work_result_contract_policies%rowtype;
  v_allocation atlas.work_allocations%rowtype;
  v_plan atlas.work_execution_plans%rowtype;
begin
  if v_uid is null then raise exception 'Authenticated employee required.' using errcode='42501'; end if;
  if p_projection_id is null then raise exception 'Worker Day projection required.' using errcode='22023'; end if;

  select * into v_projection from atlas.worker_week_projection p where p.id=p_projection_id;
  if v_projection.id is null then raise exception 'Worker Day projection was not found.' using errcode='P0002'; end if;

  select fm.farm_id into v_farm_id
  from atlas.farm_memberships fm
  where fm.id=v_projection.membership_id
    and fm.user_id=v_uid
    and fm.active;
  if v_farm_id is null then raise exception 'Worker Day projection is not available to the signed-in employee.' using errcode='42501'; end if;

  v_context:=atlas.organization_employee_worker_context_self_v1(v_farm_id,v_projection.membership_id);
  if not coalesce((v_context->>'ok')::boolean,false)
     or v_projection.organization_id is distinct from (v_context->>'organizationId')::uuid
     or v_projection.organization_membership_id is distinct from (v_context->>'organizationMembershipId')::uuid then
    raise exception 'Employee Worker Day authority required.' using errcode='42501';
  end if;

  -- A future or historic work line may be viewed in Worker Day, but is not
  -- an executable/current-service-day result reporting warrant.
  if v_projection.planned_date is distinct from (v_context->>'serviceDate')::date then
    return jsonb_build_object(
      'reportable',false,'state','not_current_service_day',
      'plannedDate',v_projection.planned_date,
      'currentServiceDate',(v_context->>'serviceDate')::date
    );
  end if;

  select array_agg(s.work_item_id order by s.work_item_id) into v_work_ids
  from atlas.worker_week_projection_sources s
  where s.projection_id=v_projection.id and s.source_role='required';

  if coalesce(array_length(v_work_ids,1),0)=0 then
    return jsonb_build_object('reportable',false,'state','no_required_company_work');
  end if;
  if array_length(v_work_ids,1)<>1 then
    return jsonb_build_object('reportable',false,'state','multiple_required_company_work','workItemIds',to_jsonb(v_work_ids));
  end if;

  select * into v_work
  from atlas.work_items w
  where w.id=v_work_ids[1]
    and w.organization_id=(v_context->>'organizationId')::uuid;
  if v_work.id is null or v_work.work_state<>'open' then
    return jsonb_build_object('reportable',false,'state','company_work_not_open','workItemId',v_work_ids[1]);
  end if;

  select * into v_policy
  from atlas.work_result_contract_policies p
  where p.contract_key=v_work.result_contract_key and p.active;
  if v_policy.contract_key is null then
    return jsonb_build_object('reportable',false,'state','ungoverned_result_contract','workItemId',v_work.id);
  end if;
  if v_policy.acceptance_mode not in ('worker_attestation','manager_acceptance') then
    return jsonb_build_object(
      'reportable',false,'state','different_result_contract','workItemId',v_work.id,
      'resultContractKey',v_policy.contract_key,'acceptanceMode',v_policy.acceptance_mode
    );
  end if;

  select * into v_allocation
  from atlas.work_allocations a
  where a.organization_id=v_work.organization_id
    and a.work_item_id=v_work.id
    and a.allocation_role='responsible'
    and a.state='active'
    and a.assignee_membership_id=(v_context->>'organizationMembershipId')::uuid
  limit 1;
  if v_allocation.id is null then
    return jsonb_build_object('reportable',false,'state','responsibility_mismatch','workItemId',v_work.id);
  end if;

  select * into v_plan
  from atlas.work_execution_plans p
  where p.organization_id=v_work.organization_id
    and p.work_item_id=v_work.id
    and p.responsible_allocation_id=v_allocation.id
    and p.assignee_membership_id=(v_context->>'organizationMembershipId')::uuid
    and p.plan_state='active'
    and p.exposure_service_date=v_projection.planned_date
  limit 1;
  if v_plan.id is null then
    return jsonb_build_object(
      'reportable',false,'state','not_on_governed_plan','workItemId',v_work.id,
      'resultContractKey',v_policy.contract_key,'acceptanceMode',v_policy.acceptance_mode
    );
  end if;

  return jsonb_build_object(
    'reportable',true,
    'state','reportable',
    'workItemId',v_work.id,
    'resultContractKey',v_policy.contract_key,
    'acceptanceMode',v_policy.acceptance_mode,
    'supportedResultKinds',jsonb_build_array('completed','blocked','partial','unable')
  );
end;
$function$;


CREATE OR REPLACE FUNCTION atlas.worker_report_company_work_projection_self_api_v1(p_projection_id uuid, p_result_kind text, p_idempotency_key text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_uid uuid:=auth.uid();
  v_projection atlas.worker_week_projection%rowtype;
  v_farm_id uuid;
  v_context jsonb;
  v_work_ids uuid[];
  v_work atlas.work_items%rowtype;
  v_policy atlas.work_result_contract_policies%rowtype;
  v_allocation atlas.work_allocations%rowtype;
  v_plan atlas.work_execution_plans%rowtype;
  v_existing atlas.work_execution_results%rowtype;
  v_existing_acceptance atlas.work_result_acceptances%rowtype;
  v_result atlas.work_execution_results%rowtype;
  v_acceptance atlas.work_result_acceptances%rowtype;
  v_kind text:=lower(btrim(coalesce(p_result_kind,'')));
  v_key text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
  v_service_date date;
begin
  if v_uid is null then raise exception 'Authenticated employee required.' using errcode='42501'; end if;
  if p_projection_id is null then raise exception 'Worker Day projection required.' using errcode='22023'; end if;
  if v_kind not in ('completed','partial','blocked','unable') then raise exception 'Unsupported Company Work result kind.' using errcode='22023'; end if;
  if v_key is null or length(v_key)>160 then raise exception 'A valid result idempotency key is required.' using errcode='22023'; end if;
  if p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception 'Company Work result payload must be an object.' using errcode='22023'; end if;

  select * into v_projection from atlas.worker_week_projection p where p.id=p_projection_id;
  if v_projection.id is null then raise exception 'Worker Day projection was not found.' using errcode='P0002'; end if;

  select fm.farm_id into v_farm_id from atlas.farm_memberships fm where fm.id=v_projection.membership_id;
  if v_farm_id is null then raise exception 'Worker delivery membership was not found.' using errcode='P0002'; end if;

  v_context:=atlas.organization_employee_worker_context_self_v1(v_farm_id,v_projection.membership_id);
  if not coalesce((v_context->>'ok')::boolean,false) then
    raise exception 'Employee Worker Day authority required: %',coalesce(v_context->>'reason','unknown') using errcode='42501';
  end if;

  if v_projection.organization_id is distinct from (v_context->>'organizationId')::uuid
     or v_projection.organization_membership_id is distinct from (v_context->>'organizationMembershipId')::uuid then
    raise exception 'Worker Day projection does not belong to the current employee relationship.' using errcode='42501';
  end if;

  -- The current plan alone must not make an arbitrary future/historic
  -- projection reportable. The selected physical delivery identity must
  -- itself be due on the worker's present governed service day.
  v_service_date:=(v_context->>'serviceDate')::date;
  if v_projection.planned_date is distinct from v_service_date then
    raise exception 'Worker Day result requires a projection for the employee current service day.'
      using errcode='23514';
  end if;

  select array_agg(s.work_item_id order by s.work_item_id) into v_work_ids
  from atlas.worker_week_projection_sources s
  where s.projection_id=v_projection.id and s.source_role='required';

  if coalesce(array_length(v_work_ids,1),0)=0 then
    return jsonb_build_object('state','no_required_company_work','projectionId',v_projection.id);
  end if;
  if array_length(v_work_ids,1)<>1 then
    return jsonb_build_object('state','multiple_required_company_work','projectionId',v_projection.id,'workItemIds',to_jsonb(v_work_ids));
  end if;

  select * into v_work
  from atlas.work_items w
  where w.id=v_work_ids[1]
    and w.organization_id=(v_context->>'organizationId')::uuid;
  if v_work.id is null then raise exception 'Required Company Work was not found in the employee organization.' using errcode='P0002'; end if;
  if v_work.work_state<>'open' then
    return jsonb_build_object('state','company_work_not_open','projectionId',v_projection.id,'workItemId',v_work.id,'workState',v_work.work_state);
  end if;
  if v_work.organization_unit_id is distinct from (v_context->>'organizationUnitId')::uuid then
    raise exception 'Company Work is outside the employee position unit.' using errcode='42501';
  end if;

  select * into v_policy
  from atlas.work_result_contract_policies p
  where p.contract_key=v_work.result_contract_key and p.active;
  if v_policy.contract_key is null then
    return jsonb_build_object('state','ungoverned_result_contract','projectionId',v_projection.id,'workItemId',v_work.id);
  end if;
  if v_policy.acceptance_mode not in ('worker_attestation','manager_acceptance') then
    return jsonb_build_object('state','different_result_contract','projectionId',v_projection.id,'workItemId',v_work.id,'acceptanceMode',v_policy.acceptance_mode);
  end if;

  select * into v_allocation
  from atlas.work_allocations a
  where a.organization_id=v_work.organization_id
    and a.work_item_id=v_work.id
    and a.allocation_role='responsible'
    and a.state='active'
    and a.assignee_membership_id=(v_context->>'organizationMembershipId')::uuid
  limit 1;
  if v_allocation.id is null then
    raise exception 'Company Work result requires current delegated Responsibility for this employee.' using errcode='23514';
  end if;

  v_service_date:=(v_context->>'serviceDate')::date;
  select * into v_plan
  from atlas.work_execution_plans p
  where p.organization_id=v_work.organization_id
    and p.work_item_id=v_work.id
    and p.responsible_allocation_id=v_allocation.id
    and p.assignee_membership_id=(v_context->>'organizationMembershipId')::uuid
    and p.plan_state='active'
    and p.exposure_service_date=v_service_date
  limit 1;
  if v_plan.id is null then
    raise exception 'Company Work result may only come from the employee current governed Worker Day plan.' using errcode='23514';
  end if;

  select * into v_existing
  from atlas.work_execution_results r
  where r.organization_id=v_work.organization_id and r.idempotency_key=v_key;
  if v_existing.id is not null then
    if v_existing.work_item_id<>v_work.id
       or v_existing.result_kind<>v_kind
       or coalesce(v_existing.metadata->>'projectionId','')<>v_projection.id::text then
      raise exception 'Company Work result idempotency key collision.' using errcode='23505';
    end if;
    select * into v_existing_acceptance
    from atlas.work_result_acceptances a
    where a.execution_result_id=v_existing.id;
    select * into v_work from atlas.work_items w where w.id=v_work.id;
    return jsonb_build_object(
      'state','deduplicated','projectionId',v_projection.id,'workItemId',v_work.id,
      'resultId',v_existing.id,'resultKind',v_existing.result_kind,
      'acceptanceDecision',v_existing_acceptance.decision,'companyWorkState',v_work.work_state
    );
  end if;

  insert into atlas.work_execution_results(
    organization_id,work_item_id,responsible_allocation_id,task_id,
    reported_by_user_id,reported_by_farm_membership_id,reported_by_organization_membership_id,
    result_kind,result_contract_key,idempotency_key,payload,metadata
  ) values(
    v_work.organization_id,v_work.id,v_allocation.id,null,
    v_uid,v_projection.membership_id,(v_context->>'organizationMembershipId')::uuid,
    v_kind,v_policy.contract_key,v_key,p_payload,
    jsonb_build_object(
      'source','worker_report_company_work_projection_self_api_v1',
      'projectionId',v_projection.id,
      'managerPlanId',v_plan.id,
      'employeeSeatId',v_context->>'employeeSeatId',
      'delegatedResponsibility',true,
      'acceptanceMode',v_policy.acceptance_mode
    )
  ) returning * into v_result;

  if v_kind='completed' and v_policy.acceptance_mode='worker_attestation' then
    insert into atlas.work_result_acceptances(
      organization_id,work_item_id,execution_result_id,decision,acceptance_kind,
      accepted_by_domain,evidence,metadata
    ) values(
      v_work.organization_id,v_work.id,v_result.id,'accepted','delegated_worker_attestation',
      'organization',
      jsonb_strip_nulls(jsonb_build_object(
        'resultContractKey',v_policy.contract_key,
        'responsibleAllocationId',v_allocation.id,
        'reportedByOrganizationMembershipId',v_result.reported_by_organization_membership_id,
        'employeeSeatId',v_context->>'employeeSeatId',
        'positionId',v_context->>'positionId',
        'positionKey',v_context->>'positionKey'
      )),
      jsonb_build_object(
        'source','worker_report_company_work_projection_self_api_v1',
        'institutionalRule','delegated_responsibility_accepts_worker_attestation'
      )
    ) returning * into v_acceptance;

    update atlas.work_items
    set work_state='completed',completed_at=coalesce(completed_at,now()),updated_at=now()
    where id=v_work.id and work_state='open';

    update atlas.work_allocations
    set state='completed',completed_at=coalesce(completed_at,now()),updated_at=now()
    where id=v_allocation.id and state='active';
  end if;

  select * into v_work from atlas.work_items w where w.id=v_work.id;

  return jsonb_build_object(
    'state',case when v_acceptance.id is not null then 'reported_and_accepted' else 'reported' end,
    'projectionId',v_projection.id,'workItemId',v_work.id,
    'resultId',v_result.id,'resultKind',v_result.result_kind,
    'resultContractKey',v_result.result_contract_key,
    'acceptanceMode',v_policy.acceptance_mode,
    'acceptanceDecision',v_acceptance.decision,
    'acceptanceKind',v_acceptance.acceptance_kind,
    'companyWorkState',v_work.work_state
  );
end;
$function$;


COMMIT;
