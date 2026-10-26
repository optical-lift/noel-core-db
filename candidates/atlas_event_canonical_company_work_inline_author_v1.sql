-- REVIEW-ONLY, source-first candidate; NOT a migration or a production operation.
-- Create ONE original canonical Company Work item directly from an authorized
-- native-Ledger Event. No employee seat, worker offer, automatic responsibility,
-- imposed Today date, physical performance claim, or Event-only checklist.
-- Apply only after disposable schema-clone/signed roles prove this contract.
create or replace function atlas.create_event_canonical_company_work_self_api_v1(
  p_organization_id uuid,
  p_ledger_id uuid,
  p_occurrence_id uuid,
  p_sentence text,
  p_source_action_id text
) returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare
  v_actor uuid;
  v_title text := nullif(btrim(coalesce(p_sentence,'')),'');
  v_action text := nullif(btrim(coalesce(p_source_action_id,'')),'');
  v_key text;
  v_work atlas.work_items%rowtype;
  v_new boolean := false;
begin
  if p_organization_id is null or p_ledger_id is null or p_occurrence_id is null
     or v_title is null or length(v_title)>500
     or v_action is null or length(v_action)>128 then
    raise exception 'Exact bound Event, Work sentence and source action ID required'
      using errcode='22023';
  end if;
  -- Verifies a real session, canonical Person, active native Ledger connection,
  -- exact active Ledger/Organization/Occurrence binding. No employee seat.
  v_actor := atlas.ledger_occurrence_shared_work_actor_self_v1(
    p_organization_id,p_ledger_id,p_occurrence_id);
  if not exists(
    select 1 from atlas.work_result_contract_policies p
     where p.contract_key='ordinary_company_work_worker_attestation_v1'
       and p.active and p.source_domain='organization'
       and p.acceptance_mode='worker_attestation'
  ) then
    raise exception 'Ordinary Company Work result contract is unavailable'
      using errcode='23514';
  end if;
  v_key := 'event-canonical-company-work:' ||
    md5(p_organization_id::text||':'||p_ledger_id::text||':'||
        p_occurrence_id::text||':'||v_actor::text||':'||v_action);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'atlas.event-canonical-work:'||p_organization_id::text||':'||v_key,0));
  select * into v_work from atlas.work_items w
   where w.organization_id=p_organization_id and w.stable_key=v_key for update;
  if v_work.id is not null then
    if v_work.title is distinct from v_title
       or v_work.created_by_user_id is distinct from auth.uid()
       or v_work.metadata->>'sourceContract'
            is distinct from 'event_canonical_company_work_v1'
       or v_work.metadata->>'sourceActionId' is distinct from v_action
       or v_work.metadata->>'createdByPersonId' is distinct from v_actor::text
       or v_work.metadata->>'ledgerId' is distinct from p_ledger_id::text
       or v_work.metadata->>'occurrenceId' is distinct from p_occurrence_id::text
       or v_work.result_contract_key is distinct from
         'ordinary_company_work_worker_attestation_v1'
       or not exists (
         select 1 from atlas.company_work_native_ledger_relevance r
          where r.organization_id=p_organization_id and r.work_item_id=v_work.id
            and r.ledger_id=p_ledger_id and r.attribution_state='active'
       )
       or not exists (
         select 1 from atlas.work_item_context_links c
          where c.organization_id=p_organization_id and c.work_item_id=v_work.id
            and c.subject_domain='temporal' and c.subject_kind='occurrence'
            and c.subject_id=p_occurrence_id
       ) then
      raise exception 'Source action already belongs to a different or withdrawn Work'
        using errcode='23505';
    end if;
  else
    -- Unassigned Work is valid original Company Work. The Event is its
    -- subject/context, NOT an alternative task identity or lifecycle authority.
    insert into atlas.work_items(
      organization_id,title,work_state,source_object_type,source_object_id,
      result_contract_key,created_by_user_id,stable_key,metadata
    ) values (
      p_organization_id,v_title,'open',null,null,
      'ordinary_company_work_worker_attestation_v1',
      auth.uid(),v_key,
      jsonb_build_object(
        'sourceContract','event_canonical_company_work_v1',
        'sourceSurface','atlas_event_notebook',
        'sourceActionId',v_action,'ledgerId',p_ledger_id,
        'occurrenceId',p_occurrence_id,'createdByPersonId',v_actor,
        'custody','institutional','originalCompanyWork',true,
        'taskDoesNotEstablishResponsibility',true,
        'eventTimeNotWorkerDay',true,'physicalPerformerNotInferred',true)
    ) returning * into v_work;
    v_new := true;

    insert into atlas.company_work_native_ledger_relevance(
      organization_id,work_item_id,ledger_id,evidence_kind,
      attestation_source_ref,attestation_reason,established_by_person_id
    ) values(
      p_organization_id,v_work.id,p_ledger_id,'participant_attested',
      'atlas.work_items:'||v_work.id::text,
      'Connected native Ledger Person authored original Company Work about an Event.',
      v_actor
    );

    insert into atlas.company_work_result_contract_bindings_v1(
      organization_id,ledger_id,work_item_id,actor_person_id,
      actor_membership_id,contract_key,reason
    ) values (
      p_organization_id,p_ledger_id,v_work.id,v_actor,null,
      'ordinary_company_work_worker_attestation_v1',
      'Unassigned original Event-related Company Work uses the ordinary worker result contract.'
    );

    perform atlas.attach_work_item_context_internal_v1(
      v_work.id,'temporal','occurrence',p_occurrence_id,'for',null,
      jsonb_build_object(
        'source','create_event_canonical_company_work_self_api_v1',
        'ledgerId',p_ledger_id,'createdByPersonId',v_actor,
        'originalCompanyWork',true),
      '{"purpose":"canonical_company_work"}'::jsonb);
  end if;
  return jsonb_build_object(
    'ok',true,'contractVersion','event_canonical_company_work_v1',
    'organizationId',p_organization_id,'ledgerId',p_ledger_id,
    'occurrenceId',p_occurrence_id,'workItemId',v_work.id,
    'workState',v_work.work_state,'resultContractKey',v_work.result_contract_key,
    'createdNow',v_new,'idempotent',not v_new,
    'assignmentCreated',false,'personDayCreated',false,
    'dueDateInvented',false,'newEventCreated',false);
end;
$function$;

create or replace function public.create_event_canonical_company_work_self_api_v1(
  p_organization_id uuid,
  p_ledger_id uuid,
  p_occurrence_id uuid,
  p_sentence text,
  p_source_action_id text
) returns jsonb language sql volatile set search_path to ''
as $function$
  select atlas.create_event_canonical_company_work_self_api_v1(
    p_organization_id,p_ledger_id,p_occurrence_id,p_sentence,p_source_action_id);
$function$;

revoke all on function atlas.create_event_canonical_company_work_self_api_v1(
 uuid,uuid,uuid,text,text) from public,anon;
revoke all on function public.create_event_canonical_company_work_self_api_v1(
 uuid,uuid,uuid,text,text) from public,anon;
grant execute on function atlas.create_event_canonical_company_work_self_api_v1(
 uuid,uuid,uuid,text,text) to authenticated;
grant execute on function public.create_event_canonical_company_work_self_api_v1(
 uuid,uuid,uuid,text,text) to authenticated;
