-- REVIEW-ONLY CANDIDATE. Not a migration; do not execute on production.
-- Atlas Event + Canonical Work Build 1: owner-recorded completion, not owner-witness testimony.
-- Owning repo: optical-lift/noel-core-db. Requires disposable-clone role/trigger tests,
-- tracked migration creation/reconciliation, and separate production DDL authority.
--
-- Intent: record the governing Ledger owner's institutional declaration that
-- assigned Work is done, without alleging worker self-report, physical performance,
-- independent eyewitness evidence, or automatic downstream domain changes.
-- Existing owner_witness and worker self-report APIs remain unchanged.
create or replace function atlas.event_work_owner_record_completion_self_api_v1(
  p_organization_id uuid,
  p_ledger_id uuid,
  p_occurrence_id uuid,
  p_work_item_id uuid,
  p_expected_allocation_id uuid,
  p_source_action_id text,
  p_note text default null
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_owner_person_id uuid;
  v_work atlas.work_items%rowtype;
  v_allocation atlas.work_allocations%rowtype;
  v_result atlas.work_execution_results%rowtype;
  v_acceptance atlas.work_result_acceptances%rowtype;
  v_key text;
  v_note text;
  v_person_count integer;
  v_reporter_record_id uuid;
begin
  if auth.uid() is null
     or p_organization_id is null or p_ledger_id is null
     or p_occurrence_id is null or p_work_item_id is null
     or p_expected_allocation_id is null
     or length(btrim(coalesce(p_source_action_id,''))) not between 1 and 128
     or length(coalesce(p_note,'')) > 1200
  then
    raise exception 'Exact authenticated Event, assigned original Work and stable action required'
      using errcode='22023';
  end if;
  v_note := nullif(btrim(coalesce(p_note,'')),'');
  -- A connected attendee is not enough: the actor must actually govern the
  -- institutional Ledger and the occurrence must belong to that Ledger.
  v_owner_person_id := atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id,p_ledger_id);
  perform atlas.ledger_occurrence_shared_work_actor_self_v1(
    p_organization_id,p_ledger_id,p_occurrence_id);

  v_key := 'event-owner-recorded-done:' || md5(
    p_organization_id::text||':'||p_work_item_id::text||':'||
    v_owner_person_id::text||':'||p_source_action_id);
  -- Use the SAME responsibility lock as worker reporting and Event assignment.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'atlas.company_work.responsibility:'||p_work_item_id::text,0));
  select * into v_work from atlas.work_items w
   where w.id=p_work_item_id and w.organization_id=p_organization_id for update;
  if v_work.id is null
     or v_work.result_contract_key <> 'ordinary_company_work_worker_attestation_v1'
     or not exists (
       select 1 from atlas.work_result_contract_policies p
        where p.contract_key=v_work.result_contract_key and p.active
          and p.source_domain='organization' and p.acceptance_mode='worker_attestation'
     )
  then
    raise exception 'Only exact ordinary canonical Company Work can use this completion route'
      using errcode='42501';
  end if;
  -- Re-read by original Work, not title, person name, or calendar text.
  if not exists (
    select 1 from atlas.work_item_context_links ctx
     join atlas.company_work_native_ledger_relevance rel
       on rel.organization_id=ctx.organization_id and rel.work_item_id=ctx.work_item_id
        and rel.ledger_id=p_ledger_id and rel.attribution_state='active'
    where ctx.organization_id=p_organization_id and ctx.work_item_id=p_work_item_id
      and ctx.subject_domain='temporal' and ctx.subject_kind='occurrence'
      and ctx.subject_id=p_occurrence_id
  ) or exists(
    select 1 from atlas.ledger_occurrence_work_actions_v1 actions
     where actions.ledger_id=p_ledger_id and actions.occurrence_id=p_occurrence_id
       and actions.work_item_id=p_work_item_id and actions.action_kind='removed'
  ) then
    raise exception 'Original Work is not currently related to this exact Event and Ledger'
      using errcode='42501';
  end if;

  -- Resolve ambiguous client/server responses by the stable original action
  -- identity BEFORE checking terminal state; never insert a second result.
  select * into v_result from atlas.work_execution_results r
   where r.organization_id=p_organization_id and r.idempotency_key=v_key;
  if v_result.id is not null then
    select * into v_acceptance from atlas.work_result_acceptances a
     where a.organization_id=p_organization_id and a.work_item_id=p_work_item_id
       and a.execution_result_id=v_result.id and a.decision='accepted';
    if v_result.work_item_id is distinct from p_work_item_id
       or v_result.responsible_allocation_id is distinct from p_expected_allocation_id
       or v_result.result_kind <> 'completed'
       or v_result.result_contract_key <> v_work.result_contract_key
       or v_result.reported_by_user_id is distinct from auth.uid()
       or v_result.metadata->>'reportMode' is distinct from 'owner_recorded_completion'
       or v_result.metadata->>'ownerPersonId' is distinct from v_owner_person_id::text
       or v_result.payload->>'ownerNote' is distinct from v_note
       or v_acceptance.id is null or v_work.work_state <> 'completed'
    then
      raise exception 'Action identity collision or accepted completion not verifiable'
        using errcode='23505';
    end if;
    return jsonb_build_object('ok',true,
      'contractVersion','event_work_owner_recorded_completion_v1',
      'idempotent',true,'workItemId',v_work.id,'workState',v_work.work_state,
      'resultId',v_result.id,'acceptanceId',v_acceptance.id,
      'responsibleAllocationId',p_expected_allocation_id,
      'recordedByPersonId',v_owner_person_id,
      'workerAttested',false,'witnessEvidenceClaimed',false);
  end if;

  if v_work.work_state <> 'open' then
    raise exception 'Work already has a terminal state; reread original source'
      using errcode='40001';
  end if;

  select count(*) into v_person_count from atlas.work_allocations a
    where a.organization_id=p_organization_id and a.work_item_id=p_work_item_id
      and a.allocation_role='responsible' and a.state='active';
  if v_person_count <> 1 then
    raise exception 'Exactly one active responsible allocation required'
      using errcode='23514';
  end if;
  select * into v_allocation from atlas.work_allocations a
   where a.id=p_expected_allocation_id and a.organization_id=p_organization_id
    and a.work_item_id=p_work_item_id and a.state='active'
    and a.allocation_role='responsible' for update;
  if v_allocation.id is null
     or v_allocation.assignee_canonical_person_id is null
     or v_allocation.establishment_basis_kind not in
       ('person_connection_receiver_uptake','delegated_under_standing_scope',
        'ledger_connection_direct_assignment')
     or v_allocation.establishment_basis->>'nativeLedgerId' is distinct from
        p_ledger_id::text
  then
    raise exception 'Expected active Ledger Person responsibility has changed'
      using errcode='40001';
  end if;

  select ipr.id into v_reporter_record_id
    from atlas.institutional_person_records ipr
   where ipr.organization_id=p_organization_id
     and ipr.person_id=v_owner_person_id and ipr.status='active'
   order by ipr.created_at limit 1;

  insert into atlas.work_execution_results(
    organization_id,work_item_id,responsible_allocation_id,
    reported_by_user_id,reported_by_organization_membership_id,
    reported_by_institutional_person_record_id,
    result_kind,result_contract_key,idempotency_key,payload,metadata
  ) values (
    p_organization_id,v_work.id,v_allocation.id,auth.uid(),null,v_reporter_record_id,
    'completed',v_work.result_contract_key,v_key,
    jsonb_strip_nulls(jsonb_build_object(
      'stateAssertion','owner_recorded_company_work_complete',
      'responsiblePersonId',v_allocation.assignee_canonical_person_id,
      'recordedByPersonId',v_owner_person_id,
      'ownerNote',v_note,
      'performedByPersonId',null,
      'workerAttested',false,
      'witnessEvidenceClaimed',false)),
    jsonb_build_object('source','event_work_owner_record_completion_self_api_v1',
      'reportMode','owner_recorded_completion',
      'ownerPersonId',v_owner_person_id,
      'responsiblePersonId',v_allocation.assignee_canonical_person_id,
      'sourceActionId',p_source_action_id,
      'ledgerId',p_ledger_id,'occurrenceId',p_occurrence_id,
      'noWitnessEvidenceRequired',true)
  ) returning * into v_result;

  insert into atlas.work_result_acceptances(
    organization_id,work_item_id,execution_result_id,decision,
    acceptance_kind,accepted_by_domain,evidence,metadata
  ) values (
    p_organization_id,v_work.id,v_result.id,'accepted',
    'owner_recorded_completion','organization',
    jsonb_build_object('recordedByPersonId',v_owner_person_id,
      'responsibleAllocationId',v_allocation.id,
      'responsiblePersonId',v_allocation.assignee_canonical_person_id,
      'notWorkerAttestation',true,'notIndependentWitnessProof',true),
    jsonb_build_object('source','event_work_owner_record_completion_self_api_v1',
      'originalWorkPreserved',true,'workerAttested',false,
      'downstreamDomainEffectNotInferred',true)
  ) returning * into v_acceptance;

  update atlas.work_items
     set work_state='completed',completed_at=now(),updated_at=now()
   where id=v_work.id and work_state='open';
  if not found then
    raise exception 'Original Work state changed during completion'
      using errcode='40001';
  end if;
  update atlas.work_allocations
     set state='completed',completed_at=now(),updated_at=now()
   where id=v_allocation.id and state='active';
  if not found then
    raise exception 'Responsible allocation changed during completion'
      using errcode='40001';
  end if;
  return jsonb_build_object('ok',true,
    'contractVersion','event_work_owner_recorded_completion_v1',
    'idempotent',false,'workItemId',v_work.id,'workState','completed',
    'resultId',v_result.id,'acceptanceId',v_acceptance.id,
    'responsibleAllocationId',v_allocation.id,
    'recordedByPersonId',v_owner_person_id,
    'workerAttested',false,'witnessEvidenceClaimed',false);
end;
$function$;

-- The public wrapper is the browser-facing source seam. The inner function
-- validates the actor and jurisdiction itself (not only browser visibility).
create or replace function public.event_work_owner_record_completion_self_api_v1(
  p_organization_id uuid,
  p_ledger_id uuid,
  p_occurrence_id uuid,
  p_work_item_id uuid,
  p_expected_allocation_id uuid,
  p_source_action_id text,
  p_note text default null
) returns jsonb
language sql
set search_path to ''
as $function$
  select atlas.event_work_owner_record_completion_self_api_v1(
    p_organization_id,p_ledger_id,p_occurrence_id,p_work_item_id,
    p_expected_allocation_id,p_source_action_id,p_note);
$function$;

revoke all on function atlas.event_work_owner_record_completion_self_api_v1(
 uuid,uuid,uuid,uuid,uuid,text,text) from public,anon;
revoke all on function public.event_work_owner_record_completion_self_api_v1(
 uuid,uuid,uuid,uuid,uuid,text,text) from public,anon;
grant execute on function atlas.event_work_owner_record_completion_self_api_v1(
 uuid,uuid,uuid,uuid,uuid,text,text) to authenticated;
grant execute on function public.event_work_owner_record_completion_self_api_v1(
 uuid,uuid,uuid,uuid,uuid,text,text) to authenticated;

-- No runtime DDL execution from this candidate; create a tracked migration
-- only after schema-clone tests, authority review, and live migration reconciliation.
