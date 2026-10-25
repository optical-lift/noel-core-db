-- Native Ledger connected-Person direct assignment of EXISTING canonical Event Work.
-- Same governance basis as connected_ledger_direct_assign, no task re-creation.
begin;

alter table atlas.event_work_responsibility_changes_v1
 alter column standing_scope_id drop not null;
alter table atlas.event_work_responsibility_changes_v1
 add column if not exists authority_basis text not null
 default 'accepted_native_ledger_standing_scope';

create function atlas.event_work_owner_assign_connected_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_occurrence_id uuid,
 p_work_item_id uuid,p_expected_allocation_id uuid,p_target_person_id uuid,
 p_reason text,p_source_action_id text
) returns jsonb language plpgsql volatile security definer set search_path to ''
as $fn$
declare
 v_actor uuid;
 v_work atlas.work_items%rowtype;
 v_prior atlas.work_allocations%rowtype;
 v_new atlas.work_allocations%rowtype;
 v_record atlas.event_work_responsibility_changes_v1%rowtype;
 v_actual_id uuid;
 v_count int;
 v_basis jsonb;
begin
 if auth.uid() is null or p_organization_id is null or p_ledger_id is null
    or p_occurrence_id is null or p_work_item_id is null or p_target_person_id is null
    or length(btrim(coalesce(p_reason,''))) not between 8 and 1200
    or length(btrim(coalesce(p_source_action_id,''))) not between 1 and 128 then
    raise exception 'Exact authenticated Person, Event Work, target, reason and action key required'
      using errcode='22023';
 end if;
 v_actor:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
 perform atlas.ledger_occurrence_shared_work_actor_self_v1(p_organization_id,p_ledger_id,p_occurrence_id);
 if not atlas.person_has_native_ledger_connection_v1(
    p_organization_id,p_ledger_id,p_target_person_id) then
    raise exception 'Receiver must have a current canonical connection to the same Ledger'
      using errcode='42501';
 end if;
 -- Canonical responsibility lock serializes this with other Work assignments.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'atlas.company_work.responsibility:'||p_work_item_id::text,0));
 select * into v_record from atlas.event_work_responsibility_changes_v1 rec
 where rec.organization_id=p_organization_id
   and rec.work_item_id=p_work_item_id
   and rec.source_action_id=p_source_action_id;
 if v_record.id is not null then
   if v_record.actor_person_id<>v_actor
      or v_record.ledger_id<>p_ledger_id
      or v_record.occurrence_id<>p_occurrence_id
      or v_record.previous_allocation_id is distinct from p_expected_allocation_id
      or v_record.recipient_person_id<>p_target_person_id
      or v_record.reason<>btrim(p_reason)
      or v_record.authority_basis<>'connected_ledger_governing_direct_obligation' then
      raise exception 'The reused action identity belongs to a different change'
        using errcode='23505';
   end if;
   return jsonb_build_object(
      'ok',true,'contractVersion','event_work_connected_direct_assignment_v1',
      'workItemId',p_work_item_id,'ledgerId',p_ledger_id,'occurrenceId',p_occurrence_id,
      'previousAllocationId',v_record.previous_allocation_id,
      'newAllocationId',v_record.new_allocation_id,
      'responsiblePersonId',v_record.recipient_person_id,
      'idempotent',true,'newWorkCreated',false,
      'originalWorkPreserved',true,'responsibilityChanged',true);
 end if;
 select * into v_work from atlas.work_items w
 where w.id=p_work_item_id and w.organization_id=p_organization_id
   and w.work_state='open'
   and w.result_contract_key='ordinary_company_work_worker_attestation_v1'
 for update;
 if v_work.id is null or not exists(
   select 1 from atlas.work_item_context_links ctx
   join atlas.company_work_native_ledger_relevance rel
    on rel.work_item_id=ctx.work_item_id and rel.organization_id=ctx.organization_id
    and rel.ledger_id=p_ledger_id and rel.attribution_state='active'
   where ctx.work_item_id=v_work.id and ctx.organization_id=p_organization_id
     and ctx.subject_domain='temporal' and ctx.subject_kind='occurrence'
     and ctx.subject_id=p_occurrence_id
 ) or exists(
   select 1 from atlas.ledger_occurrence_work_actions_v1 a
    where a.ledger_id=p_ledger_id and a.occurrence_id=p_occurrence_id
     and a.work_item_id=v_work.id and a.action_kind='removed'
 ) then
   raise exception 'Original eligible Company Work must belong to this active Event and Ledger'
    using errcode='42501';
 end if;
 if exists(select 1 from atlas.company_work_initial_responsibility_offers o
   where o.work_item_id=v_work.id and o.offer_state='offered') then
   raise exception 'Resolve the existing responsibility offer first'
    using errcode='23514';
 end if;
 select count(*), (array_agg(a.id order by a.allocated_at desc,a.id desc))[1]
  into v_count,v_actual_id
 from atlas.work_allocations a where a.work_item_id=p_work_item_id
   and a.organization_id=p_organization_id and a.state='active'
   and a.allocation_role='responsible';
 if v_count>1 then
    raise exception 'Multiple responsible people require source reconciliation'
      using errcode='23514';
 end if;
 if v_actual_id is distinct from p_expected_allocation_id then
   raise exception 'Responsibility changed; reload the original task before editing'
      using errcode='40001';
 end if;
 if v_actual_id is not null then
    select * into v_prior from atlas.work_allocations a
    where a.id=v_actual_id for update;
    if coalesce(v_prior.assignee_canonical_person_id,(
      select m.person_id from atlas.organization_memberships m
      where m.id=v_prior.assignee_membership_id
    ))=p_target_person_id then
      raise exception 'This Person is already responsible for this Work'
       using errcode='22023';
    end if;
    update atlas.work_allocations
     set state='released',released_at=now(),release_reason=btrim(p_reason),
       updated_at=now()
     where id=v_prior.id and state='active';
    -- The established execution-plan reconciler retains previous date history.
 end if;
 v_basis:=jsonb_build_object(
  'contractVersion','exact_work_responsibility_establishment_v2',
  'basisKind','ledger_connection_direct_assignment',
  'organizationId',p_organization_id,'workItemId',v_work.id,
  'nativeLedgerId',p_ledger_id,'occurrenceId',p_occurrence_id,
  'senderPersonId',v_actor,'assigneePersonId',p_target_person_id,
  'authorizationBasis','governing_principal_and_active_mutual_ledger_connections',
  'establishedAt',now());
 insert into atlas.work_allocations(
   organization_id,work_item_id,assignee_membership_id,assigned_by_membership_id,
   assignee_canonical_person_id,allocation_role,state,allocated_at,
   establishment_basis_kind,establishment_basis,metadata)
 values(p_organization_id,v_work.id,null,null,
   p_target_person_id,'responsible','active',now(),
   'ledger_connection_direct_assignment',v_basis,
   jsonb_build_object('source','existing_event_work_connected_direct_assignment_v1',
    'originalOccurrenceId',p_occurrence_id,'actorPersonId',v_actor,
    'employeeSeatRequired',false,'newWorkCreated',false,
    'recipientMayReschedule',true,'reason',btrim(p_reason)))
 returning * into v_new;
 insert into atlas.event_work_responsibility_changes_v1(
  organization_id,ledger_id,occurrence_id,work_item_id,actor_person_id,
  previous_allocation_id,new_allocation_id,recipient_person_id,
  standing_scope_id,reason,source_action_id,authority_basis
 ) values(p_organization_id,p_ledger_id,p_occurrence_id,v_work.id,v_actor,
  v_prior.id,v_new.id,p_target_person_id,null,btrim(p_reason),p_source_action_id,
  'connected_ledger_governing_direct_obligation');
 return jsonb_build_object(
    'ok',true,'contractVersion','event_work_connected_direct_assignment_v1',
    'workItemId',v_work.id,'ledgerId',p_ledger_id,'occurrenceId',p_occurrence_id,
    'previousAllocationId',v_prior.id,'newAllocationId',v_new.id,
    'responsiblePersonId',p_target_person_id,
    'idempotent',false,'newWorkCreated',false,
    'originalWorkPreserved',true,'responsibilityChanged',true,
    'workDateRequiresReview',v_prior.id is not null);
end
$fn$;
revoke all on function atlas.event_work_owner_assign_connected_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid,text,text)
 from public,anon;
grant execute on function atlas.event_work_owner_assign_connected_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid,text,text)
 to authenticated;
create function public.event_work_owner_assign_connected_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_occurrence_id uuid,
 p_work_item_id uuid,p_expected_allocation_id uuid,p_target_person_id uuid,
 p_reason text,p_source_action_id text
) returns jsonb language sql volatile set search_path to ''
as $fn$ select atlas.event_work_owner_assign_connected_self_api_v1(
 p_organization_id,p_ledger_id,p_occurrence_id,p_work_item_id,
 p_expected_allocation_id,p_target_person_id,p_reason,p_source_action_id) $fn$;
revoke all on function public.event_work_owner_assign_connected_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid,text,text) from public,anon;
grant execute on function public.event_work_owner_assign_connected_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid,text,text) to authenticated;
commit;
