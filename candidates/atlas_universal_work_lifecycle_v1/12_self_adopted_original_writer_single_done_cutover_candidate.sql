-- PROTECTED CUTOVER CANDIDATE ONLY. Existing self-adoption
-- evidence writer delegates terminal Work state to the SAME lifecycle
-- transition function as native connected-Person Work. No second Done API.
-- No user-facing permissions or production installation.
CREATE OR REPLACE FUNCTION atlas.report_self_responsible_company_work_self_api_v1(p_work_item_id uuid, p_result_kind text, p_idempotency_key text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_person uuid:=atlas.current_person_id_v1();
  v_uid uuid:=auth.uid();
  v_kind text:=lower(btrim(coalesce(p_result_kind,'')));
  v_key text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
  v_work atlas.work_items%rowtype;
  v_allocation atlas.work_allocations%rowtype;
  v_existing atlas.work_execution_results%rowtype;
  v_result atlas.work_execution_results%rowtype;
  v_acceptance atlas.work_result_acceptances%rowtype;
  v_institutional uuid;
  v_universal_receipt jsonb;
  v_history_event uuid;
begin
  if v_uid is null or v_person is null then
    raise exception 'Signed-in canonical Person required' using errcode='42501';
  end if;
  if p_work_item_id is null or v_kind not in ('completed','partial','blocked','unable')
    or v_key is null or length(v_key)>160
    or p_payload is null or jsonb_typeof(p_payload)<>'object' then
    raise exception 'Exact Work, supported result, idempotency and object payload required'
      using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'atlas.company_work.responsibility:'||p_work_item_id,0));
  select * into v_work from atlas.work_items
    where id=p_work_item_id for update;
  if v_work.id is null then
    raise exception 'Company Work not found' using errcode='P0002';
  end if;
  select a.* into v_allocation
  from atlas.work_allocations a
  join atlas.organization_memberships m
    on m.id=a.assignee_membership_id and m.organization_id=a.organization_id
      and m.person_id=v_person and m.active and m.user_id=v_uid
  where a.work_item_id=v_work.id and a.organization_id=v_work.organization_id
    and a.state in ('active','completed') and a.allocation_role='responsible'
    and a.establishment_basis_kind='self_adoption'
    and a.establishment_basis->>'sourceKind'=
      'owner_self_adoption_existing_company_work'
    and a.establishment_basis->>'selfPersonId'=v_person::text
  order by a.allocated_at desc limit 1;
  if v_allocation.id is null then
    raise exception 'Caller is not the exact self-adopted responsible Person'
      using errcode='42501';
  end if;
  select * into v_existing from atlas.work_execution_results r
    where r.organization_id=v_work.organization_id and r.idempotency_key=v_key;
  if v_existing.id is not null then
    if v_existing.work_item_id<>v_work.id or v_existing.result_kind<>v_kind
      or v_existing.responsible_allocation_id<>v_allocation.id
      or v_existing.reported_by_user_id is distinct from v_uid
      or v_existing.payload is distinct from p_payload then
      raise exception 'Result idempotency key collides' using errcode='23505';
    end if;
    IF v_kind='completed' THEN
      IF EXISTS(SELECT 1 FROM atlas.work_lifecycle_events_v1 e
        WHERE e.work_item_id=v_work.id
         AND e.event_kind='work_transition_applied'
         AND e.source_idempotency_key=v_key)
      THEN
        RETURN atlas.apply_work_lifecycle_transition_internal_v1(
          v_work.id,'complete',v_existing.id,v_key);
      END IF;
      IF v_work.work_state='completed' AND EXISTS(
        SELECT 1 FROM atlas.work_result_acceptances a
        WHERE a.execution_result_id=v_existing.id
          AND a.work_item_id=v_work.id AND a.decision='accepted')
      THEN
        SELECT e.id INTO v_history_event
        FROM atlas.work_lifecycle_events_v1 e
        WHERE e.work_item_id=v_work.id
          AND e.event_kind='historical_state_snapshot'
        ORDER BY e.sequence_no DESC LIMIT 1;
        RETURN jsonb_build_object('ok',true,
          'contractVersion','universal_work_lifecycle_transition_v1',
          'idempotent',true,'historicalRecordedCompletion',true,
          'newTransitionApplied',false,'eventId',v_history_event,
          'workItemId',v_work.id,'workState','completed',
          'originalResultId',v_existing.id,'sourceAccepted',true);
      END IF;
      RAISE EXCEPTION 'Existing self-adopted completion lacks accepted lifecycle authority'
        USING ERRCODE='23514';
    END IF;
    return jsonb_build_object('ok',true,'idempotent',true,'workItemId',v_work.id,
      'resultId',v_existing.id,'workState',v_work.work_state);
  end if;
  if v_work.work_state<>'open' or v_allocation.state<>'active' then
    raise exception 'Already terminal Work cannot be reported again' using errcode='23514';
  end if;
  if v_work.result_contract_key<>'ordinary_company_work_worker_attestation_v1'
    or not exists (
      select 1 from atlas.work_result_contract_policies policy
      where policy.contract_key=v_work.result_contract_key and policy.active
        and policy.acceptance_mode='worker_attestation'
        and policy.source_domain='organization'
    ) then
    raise exception 'This Work does not permit an ordinary self result'
      using errcode='23514';
  end if;
  select ipr.id into v_institutional
  from atlas.institutional_person_records ipr
  join atlas.organization_memberships m
    on m.institutional_person_record_id=ipr.id and m.id=v_allocation.assignee_membership_id
  where ipr.organization_id=v_work.organization_id and ipr.person_id=v_person
    and ipr.status='active';
  if v_institutional is null then
    raise exception 'Exact institutional Person attribution unavailable'
      using errcode='23514';
  end if;
  insert into atlas.work_execution_results(
    organization_id,work_item_id,responsible_allocation_id,
    reported_by_user_id,reported_by_organization_membership_id,
    reported_by_institutional_person_record_id,
    result_kind,result_contract_key,idempotency_key,payload,metadata
  ) values (
    v_work.organization_id,v_work.id,v_allocation.id,
    v_uid,v_allocation.assignee_membership_id,v_institutional,
    v_kind,v_work.result_contract_key,v_key,p_payload,
    jsonb_build_object('source','report_self_responsible_company_work_self_api_v1',
      'selfResponsiblePersonId',v_person,'employeeSeatRequired',false,
      'workerDayProjectionRequired',false,'ownerSelfAdoption',true)
  ) returning * into v_result;
  if v_kind='completed' then
    insert into atlas.work_result_acceptances(
      organization_id,work_item_id,execution_result_id,
      decision,acceptance_kind,accepted_by_domain,evidence,metadata
    ) values(
      v_work.organization_id,v_work.id,v_result.id,
      'accepted','self_responsible_person_attestation','organization',
      jsonb_build_object('responsibleAllocationId',v_allocation.id,
        'reportedByCanonicalPersonId',v_person,
        'resultContractKey',v_work.result_contract_key),
      jsonb_build_object('source','report_self_responsible_company_work_self_api_v1',
        'attestationIsOwnWork',true,'notManagerAcceptance',true)
    ) returning * into v_acceptance;
    -- This original self-responsible source still records the real Result
    -- and Acceptance. It no longer marks Work or allocation Done.
    -- A single lifecycle transition authorizes and projects the terminal state.
    v_universal_receipt:=atlas.apply_work_lifecycle_transition_internal_v1(
      v_work.id,'complete',v_result.id,v_key);
    IF v_universal_receipt->>'ok' IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Universal Work lifecycle did not accept self-owned completion'
        USING ERRCODE='23514';
    END IF;
  end if;
  IF v_kind='completed' THEN
    RETURN v_universal_receipt;
  END IF;
  return jsonb_build_object('ok',true,'idempotent',false,
    'contractVersion','self_responsible_company_work_report_v1',
    'workItemId',v_work.id,'resultId',v_result.id,'resultKind',v_kind,
    'acceptanceDecision',v_acceptance.decision,
    'workState',case when v_kind='completed' then 'completed' else 'open' end,
    'employeeSeatRequired',false,'sourceHistoryPreserved',true);
end
$function$;
