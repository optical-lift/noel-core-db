-- Atlas: exact Event Work assignment and reassignment under a
-- recipient's previously accepted, bounded native Ledger standing scope.
-- Same original Work identity, no per-task offer, no employee seat shortcut.
begin;

create table atlas.event_work_responsibility_changes_v1(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null,
 ledger_id uuid not null,
 occurrence_id uuid not null,
 work_item_id uuid not null references atlas.work_items(id),
 actor_person_id uuid not null,
 previous_allocation_id uuid references atlas.work_allocations(id),
 new_allocation_id uuid not null references atlas.work_allocations(id),
 recipient_person_id uuid not null,
 standing_scope_id uuid not null references atlas.company_work_standing_assignment_scopes(id),
 reason text not null,
 source_action_id text not null,
 recorded_at timestamptz not null default now(),
 unique(organization_id,work_item_id,source_action_id),
 constraint event_work_change_reason_length_v1 check(length(btrim(reason)) between 8 and 1200)
);
alter table atlas.event_work_responsibility_changes_v1 enable row level security;
revoke all on atlas.event_work_responsibility_changes_v1 from public,anon,authenticated;
create index event_work_responsibility_change_by_original_v1
 on atlas.event_work_responsibility_changes_v1(work_item_id,recorded_at desc);

create function atlas.event_work_responsibility_context_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_occurrence_id uuid
) returns jsonb language plpgsql stable security definer set search_path to ''
as $fn$
declare v_actor uuid;v_items jsonb;v_scopes jsonb;
begin
 v_actor:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
 perform atlas.ledger_occurrence_shared_work_actor_self_v1(
   p_organization_id,p_ledger_id,p_occurrence_id);
 -- Source-limited: only Work linked to this original canonical Occurrence.
 select coalesce(jsonb_agg(jsonb_build_object(
  'workItemId',x.work_item_id,'allocationId',x.allocation_id,
  'personEntityId',x.assignee_canonical_person_id,
  'organizationUnitId',x.organization_unit_id,
  'operationClass',x.operation_class,
  'responsibilityState',case when x.allocation_id is null then 'unassigned'
    else 'assigned' end)
  order by x.work_item_id),'[]'::jsonb) into v_items
 from (
  select w.id as work_item_id,a.id as allocation_id,a.assignee_canonical_person_id,
    w.organization_unit_id,w.operation_class
  from atlas.work_item_context_links ctx
  join atlas.work_items w on w.id=ctx.work_item_id
    and w.organization_id=p_organization_id and w.work_state='open'
  join atlas.company_work_native_ledger_relevance rel
    on rel.work_item_id=w.id and rel.organization_id=w.organization_id
    and rel.ledger_id=p_ledger_id and rel.attribution_state='active'
  left join atlas.work_allocations a on a.work_item_id=w.id
    and a.organization_id=w.organization_id and a.allocation_role='responsible'
    and a.state='active'
  where ctx.organization_id=p_organization_id and ctx.subject_domain='temporal'
    and ctx.subject_kind='occurrence' and ctx.subject_id=p_occurrence_id
    and not exists(select 1 from atlas.ledger_occurrence_work_actions_v1 rm
      where rm.work_item_id=w.id and rm.ledger_id=p_ledger_id
        and rm.occurrence_id=p_occurrence_id and rm.action_kind='removed')
  group by w.id,w.organization_unit_id,w.operation_class,a.id,a.assignee_canonical_person_id
 ) x;
 -- Show pre-accepted standing agreements only; membership/seat alone does
 -- NOT create authority to give someone a task.
 select coalesce(jsonb_agg(jsonb_build_object(
  'scopeId',s.id,'personEntityId',s.worker_person_id,
  'displayName',e.display_name,'coverageMode',s.coverage_mode,
  'operationClass',s.covered_operation_class,'organizationUnitId',s.organization_unit_id)
   order by e.display_name,s.id),'[]'::jsonb) into v_scopes
 from atlas.company_work_standing_assignment_scopes s
 join reality.entities e on e.id=s.worker_person_id
  and e.entity_kind='person' and e.identity_state='canonical'
 where s.organization_id=p_organization_id and s.ledger_id=p_ledger_id
  and s.proposed_by_person_id=v_actor and s.worker_membership_id is null
  and s.scope_state='active' and s.accepted_at is not null
  and s.accepted_by_person_id=s.worker_person_id
  and (s.valid_until is null or s.valid_until>now())
  and atlas.person_has_native_ledger_connection_v1(
    p_organization_id,p_ledger_id,s.worker_person_id);
 return jsonb_build_object('ok',true,
  'contractVersion','event_work_authorized_responsibility_v1',
  'organizationId',p_organization_id,'ledgerId',p_ledger_id,
  'occurrenceId',p_occurrence_id,'items',v_items,
  'acceptedScopes',v_scopes,'sourceOwnedWork',true,
  'standingAssentRequired',true,'selectionDoesNotCreateAuthority',true);
end
$fn$;
revoke all on function atlas.event_work_responsibility_context_self_api_v1(uuid,uuid,uuid) from public,anon;
grant execute on function atlas.event_work_responsibility_context_self_api_v1(uuid,uuid,uuid) to authenticated;
create function public.event_work_responsibility_context_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_occurrence_id uuid
) returns jsonb language sql stable set search_path to ''
as $fn$ select atlas.event_work_responsibility_context_self_api_v1(
 p_organization_id,p_ledger_id,p_occurrence_id) $fn$;
revoke all on function public.event_work_responsibility_context_self_api_v1(uuid,uuid,uuid) from public,anon;
grant execute on function public.event_work_responsibility_context_self_api_v1(uuid,uuid,uuid) to authenticated;

create function atlas.event_work_owner_assign_under_standing_scope_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_occurrence_id uuid,
 p_work_item_id uuid,p_expected_allocation_id uuid,p_scope_id uuid,
 p_reason text,p_source_action_id text
) returns jsonb language plpgsql volatile security definer set search_path to ''
as $fn$
declare
 v_actor uuid;v_work atlas.work_items%rowtype;
 v_scope atlas.company_work_standing_assignment_scopes%rowtype;
 v_old atlas.work_allocations%rowtype;v_new atlas.work_allocations%rowtype;
 v_count int;v_receipt atlas.event_work_responsibility_changes_v1%rowtype;
 v_basis jsonb;
begin
 if auth.uid() is null or p_work_item_id is null or p_scope_id is null
  or length(btrim(coalesce(p_reason,''))) not between 8 and 1200
  or length(btrim(coalesce(p_source_action_id,''))) not between 1 and 128
 then raise exception 'Original Work, accepted scope, reason and action key required'
  using errcode='22023';end if;
 v_actor:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
 perform atlas.ledger_occurrence_shared_work_actor_self_v1(
  p_organization_id,p_ledger_id,p_occurrence_id);
 perform pg_catalog.pg_advisory_xact_lock(
   pg_catalog.hashtextextended('atlas.company_work.responsibility:'||p_work_item_id::text,0));
 select * into v_receipt from atlas.event_work_responsibility_changes_v1 a
 where a.organization_id=p_organization_id and a.work_item_id=p_work_item_id
  and a.source_action_id=p_source_action_id;
 if v_receipt.id is not null then
  if v_receipt.actor_person_id<>v_actor
    or v_receipt.ledger_id<>p_ledger_id or v_receipt.occurrence_id<>p_occurrence_id
    or v_receipt.previous_allocation_id is distinct from p_expected_allocation_id
    or v_receipt.standing_scope_id<>p_scope_id
    or v_receipt.reason<>btrim(p_reason) then
   raise exception 'Reused action key changed its source facts' using errcode='23505';
  end if;
  return jsonb_build_object('ok',true,'contractVersion','event_work_scope_assignment_v1',
    'workItemId',p_work_item_id,'previousAllocationId',v_receipt.previous_allocation_id,
    'newAllocationId',v_receipt.new_allocation_id,
    'responsiblePersonId',v_receipt.recipient_person_id,'idempotent',true,
    'newWorkCreated',false,'originalWorkPreserved',true,'responsibilityChanged',true);
 end if;
 select * into v_work from atlas.work_items w
 where w.id=p_work_item_id and w.organization_id=p_organization_id
  and w.work_state='open' for update;
 if v_work.id is null or not exists(
   select 1 from atlas.work_item_context_links ctx
   join atlas.company_work_native_ledger_relevance rel
     on rel.work_item_id=ctx.work_item_id
     and rel.organization_id=ctx.organization_id and rel.ledger_id=p_ledger_id
     and rel.attribution_state='active'
   where ctx.work_item_id=v_work.id and ctx.organization_id=p_organization_id
     and ctx.subject_domain='temporal' and ctx.subject_kind='occurrence'
     and ctx.subject_id=p_occurrence_id
 ) or exists(
   select 1 from atlas.ledger_occurrence_work_actions_v1 rm
   where rm.work_item_id=v_work.id and rm.ledger_id=p_ledger_id
     and rm.occurrence_id=p_occurrence_id and rm.action_kind='removed'
 ) then
  raise exception 'Original open Work must belong to this exact active Event' using errcode='42501';
 end if;
 select * into v_scope from atlas.company_work_standing_assignment_scopes s
 where s.id=p_scope_id and s.organization_id=p_organization_id
  and s.ledger_id=p_ledger_id and s.proposed_by_person_id=v_actor
  and s.worker_membership_id is null
  and s.scope_state='active' and s.accepted_at is not null
  and s.accepted_by_person_id=s.worker_person_id
  and (s.valid_until is null or s.valid_until>now())
  and (s.coverage_mode='ledger_all_work' or
     (s.coverage_mode='operation_class' and
      v_work.organization_unit_id is not distinct from s.organization_unit_id and
      v_work.operation_class is not distinct from s.covered_operation_class))
 for update;
 if v_scope.id is null or not atlas.person_has_native_ledger_connection_v1(
   p_organization_id,p_ledger_id,v_scope.worker_person_id) then
  raise exception 'Receiver has not accepted a governing scope covering this Work'
    using errcode='23514';
 end if;
 if exists(select 1 from atlas.company_work_initial_responsibility_offers o
   where o.work_item_id=v_work.id and o.offer_state='offered') then
  raise exception 'An individual responsibility offer must be resolved first' using errcode='23514';
 end if;
 select count(*), (array_agg(a.id order by a.allocated_at desc,a.id desc))[1]
  into v_count,v_old.id from atlas.work_allocations a
 where a.work_item_id=v_work.id and a.organization_id=p_organization_id
   and a.state='active' and a.allocation_role='responsible';
 if v_count>1 then raise exception 'Multiple current responsibilities require audit' using errcode='23514'; end if;
 if v_old.id is distinct from p_expected_allocation_id then
  raise exception 'Current responsibility changed; reread this Work first' using errcode='40001';
 end if;
 if v_old.id is not null then
  select * into v_old from atlas.work_allocations where id=v_old.id for update;
  if v_old.assignee_canonical_person_id=v_scope.worker_person_id then
   raise exception 'Selected Person already carries this Work' using errcode='22023';end if;
 end if;
 -- Original Event link is verified above. Record an owner source attestation
 -- (not a fabricated source_verified row) to satisfy the existing scope guard.
 perform atlas.establish_company_work_native_ledger_relevance_self_api_v1(
  v_work.id,p_ledger_id,jsonb_build_object(
    'evidenceClass','owner_attestation',
    'sourceRef','atlas.work_item_context_links:'||p_occurrence_id::text||':'||v_work.id::text,
    'reason','Owner validated original canonical Event-to-Work linkage: '||btrim(p_reason)));
 if v_old.id is not null then
  update atlas.work_allocations
   set state='released',released_at=now(),release_reason=btrim(p_reason),updated_at=now()
   where id=v_old.id and state='active';
  -- Existing Work-plan reconciliation preserves prior dates as needing replan.
 end if;
 v_basis:=jsonb_build_object(
    'contractVersion','exact_work_responsibility_establishment_v2',
    'basisKind','delegated_under_standing_scope',
    'organizationId',p_organization_id,'workItemId',v_work.id,
    'nativeLedgerId',p_ledger_id,'scopeId',v_scope.id,
    'assigneePersonId',v_scope.worker_person_id,
    'scopeAcceptedAt',v_scope.accepted_at,'establishedAt',now());
 insert into atlas.work_allocations(
  organization_id,work_item_id,assignee_membership_id,
  assignee_canonical_person_id,assigned_by_membership_id,
  allocation_role,state,allocated_at,establishment_basis_kind,
  establishment_basis,metadata)
 values(p_organization_id,v_work.id,null,v_scope.worker_person_id,null,
  'responsible','active',now(),'delegated_under_standing_scope',v_basis,
  jsonb_build_object('source','event_work_owner_assign_under_standing_scope_v1',
    'actorPersonId',v_actor,'reason',btrim(p_reason),
    'originalOccurrenceId',p_occurrence_id,'newWorkCreated',false))
 returning * into v_new;
 insert into atlas.event_work_responsibility_changes_v1(
  organization_id,ledger_id,occurrence_id,work_item_id,actor_person_id,
  previous_allocation_id,new_allocation_id,recipient_person_id,standing_scope_id,
  reason,source_action_id)
 values(p_organization_id,p_ledger_id,p_occurrence_id,v_work.id,v_actor,
  v_old.id,v_new.id,v_scope.worker_person_id,v_scope.id,
  btrim(p_reason),p_source_action_id);
 return jsonb_build_object('ok',true,
  'contractVersion','event_work_scope_assignment_v1',
  'workItemId',v_work.id,'ledgerId',p_ledger_id,'occurrenceId',p_occurrence_id,
  'previousAllocationId',v_old.id,'newAllocationId',v_new.id,
  'responsiblePersonId',v_scope.worker_person_id,'idempotent',false,
  'newWorkCreated',false,'originalWorkPreserved',true,'responsibilityChanged',true,
  'workDateRequiresReplan',v_old.id is not null);
end
$fn$;
revoke all on function atlas.event_work_owner_assign_under_standing_scope_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid,text,text) from public,anon;
grant execute on function atlas.event_work_owner_assign_under_standing_scope_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid,text,text) to authenticated;
create function public.event_work_owner_assign_under_standing_scope_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_occurrence_id uuid,
 p_work_item_id uuid,p_expected_allocation_id uuid,p_scope_id uuid,
 p_reason text,p_source_action_id text
) returns jsonb language sql volatile set search_path to ''
as $fn$ select atlas.event_work_owner_assign_under_standing_scope_self_api_v1(
 p_organization_id,p_ledger_id,p_occurrence_id,p_work_item_id,
 p_expected_allocation_id,p_scope_id,p_reason,p_source_action_id) $fn$;
revoke all on function public.event_work_owner_assign_under_standing_scope_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid,text,text) from public,anon;
grant execute on function public.event_work_owner_assign_under_standing_scope_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid,text,text) to authenticated;
commit;
