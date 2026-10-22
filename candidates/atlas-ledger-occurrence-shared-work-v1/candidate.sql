BEGIN;

-- Atlas candidate, NOT an executed migration. Governed source generation and
-- disposable schema-clone validation must precede any protected release.
-- Owns only ordinary Ledger/Occurrence checklist Work. No employee, allocated
-- worker, optional responsibility, Worker Day, email transport, or financial authority.

ALTER TABLE atlas.work_item_context_links
  DROP CONSTRAINT work_item_context_links_subject_pair_v1;
ALTER TABLE atlas.work_item_context_links
  ADD CONSTRAINT work_item_context_links_subject_pair_v1
  CHECK (
    (subject_domain='spatial' AND subject_kind IN ('zone','place'))
    OR (subject_domain='identity' AND subject_kind IN ('identity_subject','external_relationship'))
    OR (subject_domain='temporal' AND subject_kind='occurrence')
  );

CREATE OR REPLACE FUNCTION atlas.attach_work_item_context_internal_v1(
  p_work_item_id uuid,p_subject_domain text,p_subject_kind text,
  p_subject_id uuid,p_relation_kind text,p_created_by_membership_id uuid,
  p_provenance jsonb DEFAULT '{}'::jsonb,p_metadata jsonb DEFAULT '{}'::jsonb
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','atlas'
AS $function$
declare
  v_work atlas.work_items%rowtype;
  v_domain text := lower(btrim(coalesce(p_subject_domain,'')));
  v_kind text := lower(btrim(coalesce(p_subject_kind,'')));
  v_relation text := lower(btrim(coalesce(p_relation_kind,'')));
  v_link_id uuid;
begin
  select * into v_work from atlas.work_items where id=p_work_item_id;
  if v_work.id is null then
    raise exception 'Company Work item not found.' using errcode='P0002';
  end if;
  if p_created_by_membership_id is not null and not exists (
    select 1 from atlas.organization_memberships m
    where m.id=p_created_by_membership_id and m.organization_id=v_work.organization_id and m.active
  ) then
    raise exception 'Context creator must be an active member of the work organization.' using errcode='42501';
  end if;
  if jsonb_typeof(coalesce(p_provenance,'{}'::jsonb))<>'object'
     or jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then
    raise exception 'Context provenance and metadata must be objects.' using errcode='22023';
  end if;

  if v_domain='spatial' and v_kind='zone' then
    if v_relation not in ('about','located_in','acts_on','supports') then
      raise exception 'That relation is not valid for a zone context.' using errcode='22023';
    end if;
    if not exists (
      select 1 from atlas.zones z join atlas.farms f on f.id=z.farm_id
      where z.id=p_subject_id and f.organization_id=v_work.organization_id
    ) then
      raise exception 'Zone context must belong to the work organization.' using errcode='42501';
    end if;
  elsif v_domain='spatial' and v_kind='place' then
    if v_relation not in ('about','located_in','acts_on','supports') then
      raise exception 'That relation is not valid for a place context.' using errcode='22023';
    end if;
    if not exists (
      select 1 from atlas.places p join atlas.farms f on f.id=p.farm_id
      where p.id=p_subject_id and f.organization_id=v_work.organization_id
    ) then
      raise exception 'Place context must belong to the work organization.' using errcode='42501';
    end if;
  elsif v_domain='identity' and v_kind='identity_subject' then
    if v_relation not in ('about','for','supports') then
      raise exception 'That relation is not valid for an identity subject.' using errcode='22023';
    end if;
    if not exists (
      select 1 from atlas.identity_subject_projections s
      where s.subject_id=p_subject_id and s.organization_id=v_work.organization_id
    ) then
      raise exception 'Identity subject must belong to the work organization.' using errcode='42501';
    end if;
  elsif v_domain='identity' and v_kind='external_relationship' then
    if v_relation not in ('about','for','supports') then
      raise exception 'That relation is not valid for an external relationship.' using errcode='22023';
    end if;
    if not exists (
      select 1 from atlas.external_relationships r
      where r.id=p_subject_id and r.organization_id=v_work.organization_id
    ) then
      raise exception 'External relationship must belong to the work organization.' using errcode='42501';
    end if;
  elsif v_domain='temporal' and v_kind='occurrence' then
    if v_relation not in ('about','for','supports') then
      raise exception 'That relation is not valid for an occurrence context.' using errcode='22023';
    end if;
    if not exists (
      select 1 from local_intel.occurrences o
      join atlas.organization_occurrence_bindings b
        on b.occurrence_id=o.id and b.organization_id=v_work.organization_id
          and b.binding_state='active'
      where o.id=p_subject_id
    ) then
      raise exception 'Occurrence context must have an active Organization binding.' using errcode='42501';
    end if;
  else
    raise exception 'Unsupported Company Work context subject.' using errcode='22023';
  end if;

  insert into atlas.work_item_context_links(
    organization_id,work_item_id,subject_domain,subject_kind,subject_id,relation_kind,
    created_by_membership_id,provenance,metadata
  ) values (
    v_work.organization_id,v_work.id,v_domain,v_kind,p_subject_id,v_relation,
    p_created_by_membership_id,coalesce(p_provenance,'{}'::jsonb),coalesce(p_metadata,'{}'::jsonb)
  )
  on conflict (work_item_id,subject_domain,subject_kind,subject_id,relation_kind)
  do update set
    provenance=atlas.work_item_context_links.provenance || excluded.provenance,
    metadata=atlas.work_item_context_links.metadata || excluded.metadata
  returning id into v_link_id;
  return v_link_id;
end
$function$;

-- Exact, minimally disclosed participation boundary. A Ledger Seat grants
-- no general action history, private correspondence or financial read here.
-- This checks one canonical Person, one live Ledger and a binding of this
-- particular Occurrence into both the specified Ledger and Organization.
CREATE OR REPLACE FUNCTION atlas.ledger_occurrence_shared_work_actor_self_v1(
  p_organization_id uuid,p_ledger_id uuid,p_occurrence_id uuid
) RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
declare v_actor uuid; v_access jsonb;
begin
  if auth.uid() is null or p_organization_id is null
     or p_ledger_id is null or p_occurrence_id is null then
    raise exception 'Authenticated exact Ledger and Occurrence required.' using errcode='42501';
  end if;
  v_access:=atlas.reality_access_self_api_v1();
  if v_access->>'state' is distinct from 'ready'
     or v_access->>'authenticated' is distinct from 'true' then
    raise exception 'Current Personal Atlas access required.' using errcode='42501';
  end if;
  v_actor:=atlas.current_person_id_v1();
  if v_actor is null or not atlas.person_has_native_ledger_connection_v1(
    p_organization_id,p_ledger_id,v_actor
  ) then
    raise exception 'Current canonical Person Ledger connection required.' using errcode='42501';
  end if;
  if not exists (
    select 1 from ledger.occurrence_calendar_bindings cb
    join local_intel.occurrences o on o.id=cb.occurrence_id
    join atlas.organization_occurrence_bindings ob
      on ob.occurrence_id=o.id and ob.organization_id=p_organization_id
        and ob.binding_state='active'
    where cb.ledger_id=p_ledger_id and cb.occurrence_id=p_occurrence_id
      and cb.binding_state='active'
  ) then
    raise exception 'Exact Event is not an active Occurrence of this Ledger and Organization.'
      using errcode='42501';
  end if;
  return v_actor;
end
$function$;

-- Minimal Event index: discover only exact Occurrences bound to a live
-- Ledger AND the same Organization. This is intentionally not the root Ledger
-- workspace, and does not disclose full action history or customer data.
CREATE OR REPLACE FUNCTION atlas.ledger_occurrence_shared_index_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
declare v_actor uuid;v_access jsonb;v_events jsonb;
begin
  if auth.uid() is null or p_organization_id is null or p_ledger_id is null then
    raise exception 'Authenticated exact Ledger required.' using errcode='42501';
  end if;
  v_access:=atlas.reality_access_self_api_v1();
  if v_access->>'state' is distinct from 'ready'
    or v_access->>'authenticated' is distinct from 'true' then
    raise exception 'Personal Atlas identity access required.' using errcode='42501';
  end if;
  v_actor:=atlas.current_person_id_v1();
  if v_actor is null or not atlas.person_has_native_ledger_connection_v1(
    p_organization_id,p_ledger_id,v_actor
  ) then
    raise exception 'Current exact Ledger connection required.' using errcode='42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',q.id,'title',q.title,'status',q.status,
    'startsAt',q.start_at,'endsAt',q.end_at
  ) order by q.start_at desc,q.id),'[]'::jsonb) into v_events
  from (
    select o.id,o.title,o.status,o.start_at,o.end_at
    from ledger.occurrence_calendar_bindings cb
    join local_intel.occurrences o on o.id=cb.occurrence_id
    join atlas.organization_occurrence_bindings ob
      on ob.occurrence_id=o.id and ob.organization_id=p_organization_id
        and ob.binding_state='active'
    where cb.ledger_id=p_ledger_id and cb.binding_state='active'
    order by o.start_at desc,o.id
    limit 150
  ) q;
  return jsonb_build_object(
    'ok',true,'contractVersion','ledger_occurrence_shared_index_v1',
    'organizationId',p_organization_id,'ledgerId',p_ledger_id,
    'events',v_events,'truthBoundary',jsonb_build_object(
      'onlyBoundOccurrences',true,'noCustomerData',true,
      'noGeneralLedgerHistory',true,'notGrantingWorkExecution',true));
end
$function$;

-- An ordinary shared check-off is a confirmation about Work state, not a
-- witness statement that the actor personally performed the physical work.
INSERT INTO atlas.work_result_contract_policies(
  contract_key,source_domain,acceptance_mode,active,description,metadata
) VALUES (
  'ledger_occurrence_shared_confirmation_v1','organization','domain_adapter',true,
  'Authorized Ledger collaborator confirms an ordinary Event checklist state; performer not inferred.',
  '{"source":"ledger_occurrence_shared_work_v1","workerDayRequired":false,"responsibleAllocationRequired":false,"physicalPerformerAsserted":false}'::jsonb
) ON CONFLICT (contract_key) DO NOTHING;

CREATE OR REPLACE FUNCTION atlas.ledger_occurrence_shared_work_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_occurrence_id uuid
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
declare
  v_actor uuid;
  v_event local_intel.occurrences%rowtype;
  v_items jsonb;
begin
  v_actor:=atlas.ledger_occurrence_shared_work_actor_self_v1(
    p_organization_id,p_ledger_id,p_occurrence_id);
  select * into v_event from local_intel.occurrences where id=p_occurrence_id;
  select coalesce(jsonb_agg(jsonb_build_object(
    'workItemId',q.id,'title',q.title,'state',q.work_state,
    'createdAt',q.created_at,'completedAt',q.completed_at,
    'linkedAs',q.relation_kind,'resultContractKey',q.result_contract_key
  ) order by q.created_at,q.id),'[]'::jsonb)
  into v_items
  from (
    select distinct on (w.id) w.id,w.title,w.work_state,w.created_at,
      w.completed_at,w.result_contract_key,ctx.relation_kind
    from atlas.work_item_context_links ctx
    join atlas.work_items w on w.id=ctx.work_item_id
      and w.organization_id=p_organization_id
    join atlas.company_work_native_ledger_relevance rel
      on rel.work_item_id=w.id and rel.organization_id=w.organization_id
        and rel.ledger_id=p_ledger_id and rel.attribution_state='active'
    where ctx.organization_id=p_organization_id
      and ctx.subject_domain='temporal' and ctx.subject_kind='occurrence'
      and ctx.subject_id=p_occurrence_id and ctx.relation_kind in ('for','about','supports')
      and w.work_state in ('open','completed')
    order by w.id,ctx.created_at
  ) q;
  return jsonb_build_object(
    'ok',true,'contractVersion','ledger_occurrence_shared_work_v1',
    'ledgerId',p_ledger_id,'organizationId',p_organization_id,
    'occurrence',jsonb_build_object(
      'id',v_event.id,'title',v_event.title,'status',v_event.status,
      'startsAt',v_event.start_at,'endsAt',v_event.end_at),
    'work',v_items,
    'permissions',jsonb_build_object('ordinaryWorkCreate',true,'ordinaryWorkMarkDone',true),
    'truthBoundary',jsonb_build_object('scopedToExactEvent',true,
      'notGeneralLedgerHistory',true,'noCustomerOrFinanceAccess',true,
      'notProofOfEmailSending',true,'physicalPerformerNotInferred',true));
end
$function$;

CREATE OR REPLACE FUNCTION atlas.create_ledger_occurrence_shared_work_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_occurrence_id uuid,
  p_sentence text,p_source_action_id text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
declare
  v_actor uuid;
  v_title text:=nullif(btrim(coalesce(p_sentence,'')),'');
  v_action text:=nullif(btrim(coalesce(p_source_action_id,'')),'');
  v_stable_key text;
  v_work atlas.work_items%rowtype;
  v_created boolean:=false;
begin
  if v_title is null or length(v_title)>500 or v_action is null or length(v_action)>128 then
    raise exception 'One ordinary work sentence and stable source action ID required.'
      using errcode='22023';
  end if;
  v_actor:=atlas.ledger_occurrence_shared_work_actor_self_v1(
    p_organization_id,p_ledger_id,p_occurrence_id);
  if not exists (
    select 1 from atlas.work_result_contract_policies p
    where p.contract_key='ledger_occurrence_shared_confirmation_v1' and p.active
      and p.source_domain='organization' and p.acceptance_mode='domain_adapter'
  ) then
    raise exception 'Ordinary shared confirmation policy unavailable.' using errcode='23514';
  end if;
  v_stable_key:='ledger-occurrence-shared:'||
    md5(p_ledger_id::text||':'||p_occurrence_id::text||':'||v_action);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'atlas.ledger-occurrence-work:'||p_organization_id::text||':'||v_stable_key,0));
  select * into v_work from atlas.work_items
    where organization_id=p_organization_id and stable_key=v_stable_key for update;
  if v_work.id is not null then
    if v_work.title is distinct from v_title
       or v_work.source_object_type is distinct from 'ledger_occurrence_shared_work'
       or v_work.source_object_id is distinct from p_occurrence_id
       or v_work.metadata->>'ledgerId' is distinct from p_ledger_id::text
       or v_work.metadata->>'sourceActionId' is distinct from v_action then
      raise exception 'Source action already belongs to different Work.' using errcode='23505';
    end if;
  else
    insert into atlas.work_items(
      organization_id,title,work_state,source_object_type,source_object_id,
      result_contract_key,created_by_user_id,stable_key,metadata
    ) values (
      p_organization_id,v_title,'open','ledger_occurrence_shared_work',p_occurrence_id,
      'ledger_occurrence_shared_confirmation_v1',auth.uid(),v_stable_key,
      jsonb_build_object(
        'sourceContract','ledger_occurrence_shared_work_v1',
        'ledgerId',p_ledger_id,'occurrenceId',p_occurrence_id,
        'sourceActionId',v_action,'createdByPersonId',v_actor,
        'custody','institutional','ordinarySharedChecklist',true,
        'exclusiveAssigneeAuthority',false,'workerDayRequired',false,
        'physicalPerformerNotInferred',true)
    ) returning * into v_work;
    v_created:=true;
    insert into atlas.company_work_native_ledger_relevance(
      organization_id,work_item_id,ledger_id,evidence_kind,
      attestation_source_ref,attestation_reason,established_by_person_id
    ) values (
      p_organization_id,v_work.id,p_ledger_id,'participant_attested',
      'atlas.work_items:'||v_work.id::text,
      'Connected Ledger participant authored ordinary Work inside bound Occurrence.',
      v_actor
    );
    perform atlas.attach_work_item_context_internal_v1(
      v_work.id,'temporal','occurrence',p_occurrence_id,'for',null,
      jsonb_build_object('source','create_ledger_occurrence_shared_work_self_api_v1',
        'createdByPersonId',v_actor,'ledgerId',p_ledger_id),
      '{"purpose":"ordinary_shared_work"}'::jsonb);
  end if;
  return jsonb_build_object(
    'ok',true,'contractVersion','ledger_occurrence_shared_work_v1',
    'workItemId',v_work.id,'workState',v_work.work_state,
    'ledgerId',p_ledger_id,'occurrenceId',p_occurrence_id,
    'created',v_created,'idempotent',not v_created,
    'assignmentCreated',false,'workerDayCreated',false);
end
$function$;

CREATE OR REPLACE FUNCTION atlas.mark_ledger_occurrence_shared_work_done_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_occurrence_id uuid,
  p_work_item_id uuid,p_source_action_id text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
declare
  v_actor uuid;
  v_action text:=nullif(btrim(coalesce(p_source_action_id,'')),'');
  v_key text;
  v_work atlas.work_items%rowtype;
  v_result atlas.work_execution_results%rowtype;
  v_receipt atlas.work_result_acceptances%rowtype;
  v_payload jsonb;
begin
  if p_work_item_id is null or v_action is null or length(v_action)>128 then
    raise exception 'Exact Work and one source action ID required.' using errcode='22023';
  end if;
  v_actor:=atlas.ledger_occurrence_shared_work_actor_self_v1(
    p_organization_id,p_ledger_id,p_occurrence_id);
  v_key:='ledger-occurrence-done:'||
    md5(p_ledger_id::text||':'||p_occurrence_id::text||':'||v_action);
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
    return jsonb_build_object('ok',true,'idempotent',true,
      'workItemId',v_work.id,'workState',v_work.work_state,
      'resultId',v_result.id,'markedByPersonId',v_actor);
  end if;
  if v_work.work_state='completed' then
    return jsonb_build_object('ok',true,'idempotent',false,'alreadyDone',true,
      'workItemId',v_work.id,'workState','completed',
      'markedByPersonId',null);
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
  update atlas.work_items
     set work_state='completed',completed_at=now(),updated_at=now()
   where id=v_work.id and work_state='open';
  if not found then raise exception 'Work state changed during the action.' using errcode='40001'; end if;
  return jsonb_build_object('ok',true,'idempotent',false,'alreadyDone',false,
    'workItemId',v_work.id,'workState','completed',
    'resultId',v_result.id,'acceptanceId',v_receipt.id,
    'markedByPersonId',v_actor,'physicalPerformerAsserted',false);
end
$function$;

REVOKE ALL ON FUNCTION atlas.ledger_occurrence_shared_work_actor_self_v1(uuid,uuid,uuid)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.ledger_occurrence_shared_index_self_api_v1(uuid,uuid)
  FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION atlas.ledger_occurrence_shared_work_self_api_v1(uuid,uuid,uuid)
  FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION atlas.create_ledger_occurrence_shared_work_self_api_v1(uuid,uuid,uuid,text,text)
  FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION atlas.mark_ledger_occurrence_shared_work_done_self_api_v1(uuid,uuid,uuid,uuid,text)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION atlas.ledger_occurrence_shared_index_self_api_v1(uuid,uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.ledger_occurrence_shared_work_self_api_v1(uuid,uuid,uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.create_ledger_occurrence_shared_work_self_api_v1(uuid,uuid,uuid,text,text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.mark_ledger_occurrence_shared_work_done_self_api_v1(uuid,uuid,uuid,uuid,text)
  TO authenticated;

COMMIT;
