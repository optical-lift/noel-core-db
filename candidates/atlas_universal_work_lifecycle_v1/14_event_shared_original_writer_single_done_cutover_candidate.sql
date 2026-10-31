-- CUTOVER CANDIDATE ONLY: existing native connected-Person Event
-- shared checklist Result/Acceptance writer delegates terminal state to
-- the SAME universal event-sourced Work transition. Marking the checklist
-- never asserts physical performance. No new Done API, no permissions.
-- The native Ledger and Occurrence source guards remain unchanged.
CREATE OR REPLACE FUNCTION atlas.mark_ledger_occurrence_shared_work_done_self_api_v1(p_organization_id uuid, p_ledger_id uuid, p_occurrence_id uuid, p_work_item_id uuid, p_source_action_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid;
  v_action text:=nullif(btrim(coalesce(p_source_action_id,'')),'');
  v_key text;
  v_work atlas.work_items%rowtype;
  v_result atlas.work_execution_results%rowtype;
  v_receipt atlas.work_result_acceptances%rowtype;
  v_payload jsonb;
  v_universal_receipt jsonb;
  v_history_event uuid;
begin
  if p_work_item_id is null or v_action is null or length(v_action)>128 then
    raise exception 'Exact Work and one source action ID required.' using errcode='22023';
  end if;
  v_actor:=atlas.ledger_occurrence_shared_work_actor_self_v1(
    p_organization_id,p_ledger_id,p_occurrence_id);
  if not exists (
    select 1 from atlas.work_result_contract_policies policy
    where policy.contract_key='ledger_occurrence_shared_confirmation_v1'
      and policy.active and policy.source_domain='organization'
      and policy.acceptance_mode='domain_adapter'
  ) then
    raise exception 'Ordinary shared confirmation policy unavailable.' using errcode='23514';
  end if;
  v_key:='ledger-occurrence-done:'||
    md5(p_ledger_id::text||':'||p_occurrence_id::text||':'||v_actor::text||':'||v_action);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'atlas.company_work.shared-state:'||p_work_item_id::text,0));
  select * into v_work from atlas.work_items
    where id=p_work_item_id and organization_id=p_organization_id for update;
  if v_work.id is null or v_work.source_object_type is distinct from 'ledger_occurrence_shared_work'
     or v_work.source_object_id is distinct from p_occurrence_id
     or v_work.result_contract_key is distinct from 'ledger_occurrence_shared_confirmation_v1'
     or v_work.metadata->>'sourceContract' is distinct from 'ledger_occurrence_shared_work_v1'
     or v_work.metadata->>'ledgerId' is distinct from p_ledger_id::text
     or not exists (
       select 1 from atlas.work_item_context_links ctx
       join atlas.company_work_native_ledger_relevance rel
         on rel.organization_id=ctx.organization_id and rel.work_item_id=ctx.work_item_id
           and rel.ledger_id=p_ledger_id and rel.attribution_state='active'
       where ctx.organization_id=p_organization_id and ctx.work_item_id=p_work_item_id
         and ctx.subject_domain='temporal' and ctx.subject_kind='occurrence'
         and ctx.subject_id=p_occurrence_id and ctx.relation_kind='for'
     ) then
    raise exception 'Not ordinary Work of this exact Ledger Event.' using errcode='42501';
  end if;

  select * into v_result from atlas.work_execution_results r
    where r.organization_id=p_organization_id and r.idempotency_key=v_key;
  if v_result.id is not null then
    if v_result.work_item_id<>v_work.id
       or v_result.reported_by_user_id is distinct from auth.uid()
       or v_result.result_kind<>'completed'
       or v_result.result_contract_key<>v_work.result_contract_key then
      raise exception 'Shared work action idempotency collision.' using errcode='23505';
    end if;
    IF NOT EXISTS (SELECT 1 FROM atlas.work_result_acceptances acc
      WHERE acc.execution_result_id=v_result.id
        AND acc.work_item_id=v_work.id AND acc.decision='accepted'
        AND acc.acceptance_kind='shared_checklist_state_confirmation') THEN
      RAISE EXCEPTION 'Original shared Event result lacks accepted evidence'
        USING ERRCODE='42501'; END IF;
    IF EXISTS(SELECT 1 FROM atlas.work_lifecycle_events_v1 e
      WHERE e.work_item_id=v_work.id
        AND e.event_kind='work_transition_applied'
        AND e.source_idempotency_key=v_key) THEN
      RETURN atlas.apply_work_lifecycle_transition_internal_v1(
        v_work.id,'complete',v_result.id,v_key);
    END IF;
    IF v_work.work_state='completed' THEN
      SELECT e.id INTO v_history_event FROM atlas.work_lifecycle_events_v1 e
      WHERE e.work_item_id=v_work.id
        AND e.event_kind='historical_state_snapshot'
      ORDER BY e.sequence_no DESC LIMIT 1;
      RETURN jsonb_build_object('ok',true,
        'contractVersion','universal_work_lifecycle_transition_v1',
        'idempotent',true,'historicalRecordedCompletion',true,
        'newTransitionApplied',false,'eventId',v_history_event,
        'workItemId',v_work.id,'workState','completed',
        'originalResultId',v_result.id,'markedByPersonId',v_actor,
        'personalPerformanceNotClaimed',true);
    END IF;
    RAISE EXCEPTION 'Existing Event evidence has no accepted lifecycle event'
      USING ERRCODE='23514';
  end if;
  if v_work.work_state='completed' then
    -- Existing prior completion belongs to its original actor. Do not
    -- relabel that action as the current caller or fabricate a new Done.
    SELECT e.id INTO v_history_event FROM atlas.work_lifecycle_events_v1 e
    WHERE e.work_item_id=v_work.id
      AND e.event_kind='historical_state_snapshot'
    ORDER BY e.sequence_no DESC LIMIT 1;
    RETURN jsonb_build_object('ok',true,
      'contractVersion','universal_work_lifecycle_transition_v1',
      'idempotent',false,'alreadyDone',true,'historicalRecordedCompletion',true,
      'newTransitionApplied',false,'eventId',v_history_event,
      'workItemId',v_work.id,'workState','completed',
      'markedByPersonId',null,'personalPerformanceNotClaimed',true);
  end if;
  if v_work.work_state<>'open' then
    raise exception 'Only outstanding ordinary Event Work may be marked done.'
      using errcode='23514';
  end if;
  v_payload:=jsonb_build_object(
    'stateAssertion','ordinary_shared_work_marked_done',
    'markedByPersonId',v_actor,
    'performedByPersonId',null,
    'personalPerformanceNotClaimed',true,
    'sourceActionId',v_action);
  insert into atlas.work_execution_results(
    organization_id,work_item_id,responsible_allocation_id,
    reported_by_user_id,reported_by_organization_membership_id,
    result_kind,result_contract_key,idempotency_key,payload,metadata
  ) values (
    p_organization_id,v_work.id,null,
    auth.uid(),null,'completed',v_work.result_contract_key,v_key,v_payload,
    jsonb_build_object('source','mark_ledger_occurrence_shared_work_done_self_api_v1',
      'ledgerId',p_ledger_id,'occurrenceId',p_occurrence_id,
      'actorPersonId',v_actor,'notWorkerResult',true,'allocationNotRequired',true)
  ) returning * into v_result;
  insert into atlas.work_result_acceptances(
    organization_id,work_item_id,execution_result_id,
    decision,acceptance_kind,accepted_by_domain,evidence,metadata
  ) values (
    p_organization_id,v_work.id,v_result.id,
    'accepted','shared_checklist_state_confirmation','organization',
    jsonb_build_object('markedByPersonId',v_actor,
      'sourceActionId',v_action,'physicalPerformerAsserted',false),
    jsonb_build_object('source','ledger_occurrence_shared_work_v1',
      'authority','active_Ledger_Person_connection_exact_Event',
      'notDelegatedWorkerAcceptance',true)
  ) returning * into v_receipt;
  -- One common lifecycle command owns ALL terminal Work state. The
  -- original Event writer only validates and records the source assertion.
  v_universal_receipt:=atlas.apply_work_lifecycle_transition_internal_v1(
    v_work.id,'complete',v_result.id,v_key);
  IF v_universal_receipt->>'ok' IS DISTINCT FROM 'true' THEN
     RAISE EXCEPTION 'Shared Event lifecycle completion was not accepted'
       USING ERRCODE='23514'; END IF;
  RETURN v_universal_receipt;
end
$function$;
