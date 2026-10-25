-- Atlas Work Focus: delegated Ledger direct-obligation reassignment.
-- Source-only; exact original Work, no offer, acceptance question or duplicated Work.
begin;
create table atlas.work_focus_direct_reassignments_v1(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null,
 ledger_id uuid not null,
 work_item_id uuid not null references atlas.work_items(id),
 actor_person_id uuid not null,
 previous_allocation_id uuid not null references atlas.work_allocations(id),
 next_allocation_id uuid not null references atlas.work_allocations(id),
 previous_person_id uuid not null,
 next_person_id uuid not null,
 reason text not null,
 source_action_id text not null,
 recorded_at timestamptz not null default now(),
 constraint work_focus_reassignment_action_unique_v1 unique(organization_id,work_item_id,source_action_id),
 constraint work_focus_reassignment_reason_len_v1 check(length(btrim(reason)) between 8 and 1200)
);
create index work_focus_reassignment_history_idx_v1
 on atlas.work_focus_direct_reassignments_v1(work_item_id,recorded_at desc);
alter table atlas.work_focus_direct_reassignments_v1 enable row level security;
revoke all on atlas.work_focus_direct_reassignments_v1 from public,anon,authenticated;

create function atlas.work_focus_owner_reassignment_preflight_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid
) returns jsonb language plpgsql stable security definer set search_path to ''
as $fn$
declare v_actor uuid;v_work atlas.work_items%rowtype;v_current atlas.work_allocations%rowtype;
begin
 if auth.uid() is null or p_organization_id is null or p_ledger_id is null
   or p_work_item_id is null then
   raise exception 'Signed Work identity required' using errcode='42501';
 end if;
 v_actor:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
 select * into v_work from atlas.work_items
 where id=p_work_item_id and organization_id=p_organization_id;
 if v_work.id is null or v_work.work_state<>'open'
   or v_work.source_object_type<>'ledger_connected_direct_task'
   or v_work.metadata->>'nativeLedgerId' is distinct from p_ledger_id::text
   or not exists(
    select 1 from atlas.company_work_native_ledger_relevance rel
    where rel.organization_id=p_organization_id and rel.work_item_id=p_work_item_id
      and rel.ledger_id=p_ledger_id and rel.attribution_state='active'
      and (rel.evidence_kind in ('owner_attested','participant_attested') or
        (rel.evidence_kind='source_verified' and exists(
          select 1 from atlas.company_work_native_ledger_exact_source_v1(
            p_work_item_id,p_ledger_id) proof
          where proof.source_schema=rel.source_schema
            and proof.source_table=rel.source_table and proof.source_id=rel.source_id)))
   ) then
   raise exception 'Only original open directly delegated Ledger Work can be reassigned' using errcode='42501';
 end if;
 select * into v_current from atlas.work_allocations a
 where a.work_item_id=v_work.id and a.organization_id=p_organization_id
   and a.state='active' and a.allocation_role='responsible'
   and a.assignee_membership_id is null and a.assignee_canonical_person_id is not null
   and a.establishment_basis_kind='ledger_connection_direct_assignment'
   and a.establishment_basis->>'nativeLedgerId'=p_ledger_id::text
 order by a.allocated_at desc,a.id desc limit 1;
 if v_current.id is null or (select count(*) from atlas.work_allocations a
   where a.work_item_id=v_work.id and a.state='active' and a.allocation_role='responsible')<>1
 then raise exception 'One exact active direct assignment required' using errcode='23514'; end if;
 return jsonb_build_object('ok',true,
  'contractVersion','canonical_work_direct_reassignment_preflight_v1',
  'workItemId',v_work.id,'organizationId',p_organization_id,'ledgerId',p_ledger_id,
  'currentPersonId',v_current.assignee_canonical_person_id,
  'currentAllocationId',v_current.id,'canReassign',true);
end
$fn$;
revoke all on function atlas.work_focus_owner_reassignment_preflight_self_api_v1(uuid,uuid,uuid) from public,anon;
grant execute on function atlas.work_focus_owner_reassignment_preflight_self_api_v1(uuid,uuid,uuid) to authenticated;
create function public.work_focus_owner_reassignment_preflight_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid
) returns jsonb language sql stable set search_path to ''
as $fn$
 select atlas.work_focus_owner_reassignment_preflight_self_api_v1(
  p_organization_id,p_ledger_id,p_work_item_id)
$fn$;
revoke all on function public.work_focus_owner_reassignment_preflight_self_api_v1(uuid,uuid,uuid) from public,anon;
grant execute on function public.work_focus_owner_reassignment_preflight_self_api_v1(uuid,uuid,uuid) to authenticated;

create function atlas.work_focus_owner_reassign_direct_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
 p_expected_allocation_id uuid,p_target_person_id uuid,p_reason text,p_source_action_id text
) returns jsonb language plpgsql volatile security definer set search_path to ''
as $fn$
declare
 v_actor uuid;v_work atlas.work_items%rowtype;v_old atlas.work_allocations%rowtype;
 v_new atlas.work_allocations%rowtype;v_plan atlas.work_execution_plans%rowtype;
 v_receipt atlas.work_focus_direct_reassignments_v1%rowtype;v_basis jsonb;
begin
 if auth.uid() is null or p_expected_allocation_id is null or p_target_person_id is null
   or length(btrim(coalesce(p_reason,''))) not between 8 and 1200
   or length(btrim(coalesce(p_source_action_id,''))) not between 1 and 128 then
   raise exception 'Exact current allocation, target, reason and action identity required' using errcode='22023';
 end if;
 v_actor:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'atlas.company_work.responsibility:'||p_work_item_id::text,0));
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'atlas.company_work.plan:'||p_work_item_id::text,0));
 -- An idempotent retry remains attributable even after the original allocation changed.
 select * into v_receipt from atlas.work_focus_direct_reassignments_v1 r
 where r.organization_id=p_organization_id and r.work_item_id=p_work_item_id
  and r.source_action_id=p_source_action_id;
 if v_receipt.id is not null then
   if v_receipt.actor_person_id<>v_actor
     or v_receipt.ledger_id<>p_ledger_id
     or v_receipt.previous_allocation_id<>p_expected_allocation_id
     or v_receipt.next_person_id<>p_target_person_id
     or v_receipt.reason<>btrim(p_reason) then
     raise exception 'Reassignment action identity collision' using errcode='23505'; end if;
   return jsonb_build_object('ok',true,'idempotent',true,
     'contractVersion','canonical_work_direct_reassignment_v1',
     'workItemId',p_work_item_id,'previousAllocationId',v_receipt.previous_allocation_id,
     'newAllocationId',v_receipt.next_allocation_id,
     'currentResponsiblePersonId',v_receipt.next_person_id,
     'originalWorkPreserved',true,'newWorkCreated',false);
 end if;
 -- Revalidate exact source and Ledger after acquiring the responsibility lock.
 perform atlas.work_focus_owner_reassignment_preflight_self_api_v1(
  p_organization_id,p_ledger_id,p_work_item_id);
 select * into v_work from atlas.work_items w
 where w.id=p_work_item_id and w.organization_id=p_organization_id for update;
 select * into v_old from atlas.work_allocations a
 where a.id=p_expected_allocation_id and a.work_item_id=p_work_item_id
   and a.organization_id=p_organization_id and a.state='active'
   and a.assignee_membership_id is null
   and a.establishment_basis_kind='ledger_connection_direct_assignment'
   and a.establishment_basis->>'nativeLedgerId'=p_ledger_id::text for update;
 if v_old.id is null then
   raise exception 'Responsibility changed while this task was open; reload first' using errcode='40001'; end if;
 if v_old.assignee_canonical_person_id=p_target_person_id then
   raise exception 'The selected Person already carries this Work' using errcode='22023'; end if;
 if not atlas.person_has_native_ledger_connection_v1(
  p_organization_id,p_ledger_id,p_target_person_id) then
   raise exception 'Target Person must have an active verified connection to the same Ledger' using errcode='42501'; end if;
 select * into v_plan from atlas.work_execution_plans p
 where p.work_item_id=p_work_item_id and p.organization_id=p_organization_id
   and p.plan_state in ('active','needs_replan') for update;
 if v_plan.id is not null then
   if v_plan.responsible_allocation_id<>v_old.id then
     raise exception 'Active plan belongs to a different responsibility' using errcode='23514'; end if;
   update atlas.work_execution_plans set plan_state='withdrawn',plan_reason=p_reason,
     metadata=metadata||jsonb_build_object('sourceChange','canonical_work_owner_reassignment_v1')
     where id=v_plan.id;
   insert into atlas.work_execution_plan_events(
     organization_id,work_item_id,plan_id,event_kind,
     from_planned_service_date,from_exposure_service_date,reason,metadata
   ) values(p_organization_id,p_work_item_id,v_plan.id,'withdrawn',
     v_plan.planned_service_date,v_plan.exposure_service_date,p_reason,
     jsonb_build_object('source','canonical_work_owner_reassignment_v1',
       'priorAllocationId',v_old.id));
 end if;
 update atlas.work_allocations set state='released',released_at=now(),release_reason=p_reason,
   updated_at=now() where id=v_old.id and state='active';
 v_basis:=jsonb_build_object(
   'basisKind','ledger_connection_direct_assignment',
   'contractVersion','exact_work_responsibility_establishment_v2',
   'organizationId',p_organization_id,'nativeLedgerId',p_ledger_id,
   'workItemId',p_work_item_id,'senderPersonId',v_actor,
   'assigneePersonId',p_target_person_id,'establishedAt',now(),
   'authorizationBasis','owner_direct_reassignment_existing_work');
 insert into atlas.work_allocations(
  organization_id,work_item_id,allocation_role,state,
  assignee_canonical_person_id,establishment_basis_kind,establishment_basis,metadata
 ) values(
  p_organization_id,p_work_item_id,'responsible','active',
  p_target_person_id,'ledger_connection_direct_assignment',v_basis,
  jsonb_build_object('source','canonical_work_owner_direct_reassignment_v1',
    'employeeSeatRequired',false,'recipientMayReschedule',true)
 ) returning * into v_new;
 insert into atlas.work_focus_direct_reassignments_v1(
  organization_id,ledger_id,work_item_id,actor_person_id,
  previous_allocation_id,next_allocation_id,previous_person_id,next_person_id,reason,source_action_id
 ) values(
  p_organization_id,p_ledger_id,p_work_item_id,v_actor,
  v_old.id,v_new.id,v_old.assignee_canonical_person_id,p_target_person_id,
  btrim(p_reason),p_source_action_id
 ) returning * into v_receipt;
 return jsonb_build_object('ok',true,'idempotent',false,
  'contractVersion','canonical_work_direct_reassignment_v1',
  'workItemId',v_work.id,'previousAllocationId',v_old.id,
  'newAllocationId',v_new.id,'currentResponsiblePersonId',p_target_person_id,
  'oldPlanWithdrawn',v_plan.id is not null,
  'originalWorkPreserved',true,'newWorkCreated',false);
end
$fn$;
revoke all on function atlas.work_focus_owner_reassign_direct_self_api_v1(uuid,uuid,uuid,uuid,uuid,text,text)
 from public,anon;
grant execute on function atlas.work_focus_owner_reassign_direct_self_api_v1(uuid,uuid,uuid,uuid,uuid,text,text)
 to authenticated;
create function public.work_focus_owner_reassign_direct_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
 p_expected_allocation_id uuid,p_target_person_id uuid,p_reason text,p_source_action_id text
) returns jsonb language sql volatile set search_path to ''
as $fn$
 select atlas.work_focus_owner_reassign_direct_self_api_v1(
  p_organization_id,p_ledger_id,p_work_item_id,p_expected_allocation_id,
  p_target_person_id,p_reason,p_source_action_id)
$fn$;
revoke all on function public.work_focus_owner_reassign_direct_self_api_v1(uuid,uuid,uuid,uuid,uuid,text,text)
 from public,anon;
grant execute on function public.work_focus_owner_reassign_direct_self_api_v1(uuid,uuid,uuid,uuid,uuid,text,text)
 to authenticated;
commit;
