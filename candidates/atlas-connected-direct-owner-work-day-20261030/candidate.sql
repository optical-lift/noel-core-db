-- SOURCE ONLY: Atlas #480 / #487. Not a production migration.
-- Repair existing authenticated owner date writer to admit legitimate direct
-- connected Person Work, reusing the same original Work and native Ledger.
-- All owner, signed actor, current native Ledger, date window, action history,
-- and responsibility guards remain. No new role or table grants.
CREATE OR REPLACE FUNCTION atlas.owner_set_connected_person_work_day_self_api_v1(p_work_item_id uuid, p_ledger_id uuid, p_service_date date, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_work atlas.work_items%rowtype;
  v_allocation atlas.work_allocations%rowtype;
  v_plan atlas.work_execution_plans%rowtype;
  v_old atlas.work_execution_plans%rowtype;
  v_owner uuid;
  v_owner_member uuid;
  v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
  v_window jsonb;
  v_event text;
begin
  if auth.uid() is null or p_work_item_id is null or p_ledger_id is null
    or v_reason is null or length(v_reason) not between 12 and 1200 then
    raise exception 'Exact owner Work, Ledger and meaningful planning reason required.'
      using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'atlas.company_work.responsibility:'||p_work_item_id::text,0));
  perform pg_advisory_xact_lock(hashtextextended(
    'atlas.company_work.plan:'||p_work_item_id::text,0));
  select * into v_work from atlas.work_items
    where id=p_work_item_id and work_state='open' for update;
  if v_work.id is null then raise exception 'Open Work required for date changes.'
    using errcode='23514'; end if;
  v_owner:=atlas.company_work_native_ledger_owner_self_v1(
    v_work.organization_id,p_ledger_id);
  v_owner_member:=atlas.current_effective_organization_membership_v1(
    v_work.organization_id);
  if not exists (
    select 1 from atlas.organization_memberships m
    where m.id=v_owner_member and m.organization_id=v_work.organization_id
      and m.person_id=v_owner and m.role='owner' and m.active
  ) then raise exception 'Current authenticated owner membership required.'
    using errcode='42501'; end if;
  if not exists (
    select 1 from atlas.company_work_native_ledger_relevance rel
    where rel.organization_id=v_work.organization_id
      and rel.work_item_id=v_work.id
      and rel.ledger_id=p_ledger_id and rel.attribution_state='active'
      and (rel.evidence_kind in ('owner_attested','participant_attested') or
        (rel.evidence_kind='source_verified' and exists (
          select 1 from atlas.company_work_native_ledger_exact_source_v1(
            v_work.id,p_ledger_id) proof
          where proof.source_schema=rel.source_schema
            and proof.source_table=rel.source_table
            and proof.source_id=rel.source_id
        )))
  ) then raise exception 'Exact Ledger relevance required.' using errcode='42501'; end if;
  select * into v_allocation from atlas.work_allocations a
    where a.work_item_id=v_work.id and a.organization_id=v_work.organization_id
      and a.allocation_role='responsible' and a.state='active'
      and a.assignee_membership_id is null
      and a.assignee_canonical_person_id is not null
      and a.establishment_basis_kind in (
        'delegated_under_standing_scope','person_connection_receiver_uptake','original_subject_direct_assignment_v1','ledger_connection_direct_assignment')
      and a.establishment_basis->>'nativeLedgerId'=p_ledger_id::text
    limit 1;
  if v_allocation.id is null or not atlas.person_has_native_ledger_connection_v1(
    v_work.organization_id,p_ledger_id,v_allocation.assignee_canonical_person_id) then
    raise exception 'Active connected Person responsibility required.'
      using errcode='23514';
  end if;
  select * into v_old from atlas.work_execution_plans
    where work_item_id=v_work.id and plan_state in ('active','needs_replan')
    for update;
  if v_old.id is not null and
    v_old.responsible_allocation_id<>v_allocation.id then
    raise exception 'Current plan belongs to different responsibility.'
      using errcode='23514';
  end if;

  if p_service_date is null then
    if v_old.id is null then
      return jsonb_build_object('ok',true,
        'contractVersion','native_person_work_plan_v1',
        'state','already_unplanned','workItemId',v_work.id,
        'ledgerId',p_ledger_id,'responsiblePersonId',
        v_allocation.assignee_canonical_person_id,'newWorkCreated',false);
    end if;
    update atlas.work_execution_plans
      set plan_state='withdrawn',plan_reason=v_reason,
      metadata=metadata||jsonb_build_object(
        'sourceChange','native_person_owner_unplan_v1',
        'withdrawalReason',v_reason)
    where id=v_old.id and plan_state in ('active','needs_replan');
    insert into atlas.work_execution_plan_events(
      organization_id,work_item_id,plan_id,event_kind,
      from_planned_service_date,from_exposure_service_date,
      actor_membership_id,reason,metadata)
    values (v_work.organization_id,v_work.id,v_old.id,'withdrawn',
      v_old.planned_service_date,v_old.exposure_service_date,
      v_owner_member,v_reason,
      jsonb_build_object('source','native_person_owner_unplan_v1'));
    return jsonb_build_object('ok',true,
      'contractVersion','native_person_work_plan_v1',
      'state','unplanned','workItemId',v_work.id,'ledgerId',p_ledger_id,
      'planId',v_old.id,'responsiblePersonId',
      v_allocation.assignee_canonical_person_id,'newWorkCreated',false);
  end if;
  v_window:=atlas.company_work_execution_plan_window_check_v1(
    v_work.id,p_service_date);
  if not coalesce((v_window->>'allowed')::boolean,false) then
    raise exception 'Selected date conflicts with source-owned Work window (%).',
      v_window->>'state' using errcode='23514';
  end if;
  if v_old.id is null then
    insert into atlas.work_execution_plans(
      organization_id,work_item_id,responsible_allocation_id,
      assignee_membership_id,planned_by_membership_id,
      plan_state,first_planned_service_date,planned_service_date,
      exposure_service_date,plan_reason,metadata)
    values (v_work.organization_id,v_work.id,v_allocation.id,null,
      v_owner_member,'active',p_service_date,p_service_date,
      p_service_date,v_reason,
      jsonb_build_object('source','native_person_owner_plan_v1'))
    returning * into v_plan;
    v_event:='planned';
  else
    update atlas.work_execution_plans
      set planned_service_date=p_service_date,exposure_service_date=p_service_date,
        plan_state='active',plan_reason=v_reason,
        planned_by_membership_id=v_owner_member,
        metadata=metadata||jsonb_build_object(
          'sourceChange','native_person_owner_plan_v1'),
        rollover_count=0
      where id=v_old.id returning * into v_plan;
    v_event:=case when v_old.planned_service_date is distinct from p_service_date
      then 'rescheduled' else 'planned' end;
  end if;
  insert into atlas.work_execution_plan_events(
    organization_id,work_item_id,plan_id,event_kind,
    from_planned_service_date,to_planned_service_date,
    from_exposure_service_date,to_exposure_service_date,
    actor_membership_id,reason,metadata)
  values (v_work.organization_id,v_work.id,v_plan.id,v_event,
    v_old.planned_service_date,v_plan.planned_service_date,
    v_old.exposure_service_date,v_plan.exposure_service_date,
    v_owner_member,v_reason,
    jsonb_build_object('source','native_person_owner_plan_v1'));
  return jsonb_build_object('ok',true,
    'contractVersion','native_person_work_plan_v1',
    'state','planned','workItemId',v_work.id,
    'ledgerId',p_ledger_id,'planId',v_plan.id,
    'plannedServiceDate',v_plan.planned_service_date,
    'responsiblePersonId',v_allocation.assignee_canonical_person_id,
    'newWorkCreated',false,'workerReadProven',false);
end
$function$;
