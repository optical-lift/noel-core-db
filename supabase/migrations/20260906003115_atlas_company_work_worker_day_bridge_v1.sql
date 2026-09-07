create or replace function atlas.company_work_execution_membership_check_v1(
  p_work_item_id uuid,
  p_assignee_membership_id uuid,
  p_service_date date
) returns jsonb
language plpgsql stable security definer
set search_path='pg_catalog','atlas'
as $$
declare
  v_work atlas.work_items%rowtype;
  v_org_member atlas.organization_memberships%rowtype;
  v_farm_id uuid;
  v_count integer:=0;
  v_farm_membership_id uuid;
begin
  select * into v_work from atlas.work_items where id=p_work_item_id;
  if v_work.id is null then return jsonb_build_object('allowed',false,'state','missing_work'); end if;
  if not atlas.organization_membership_eligible_on_date_v1(p_assignee_membership_id,v_work.organization_id,p_service_date) then
    return jsonb_build_object('allowed',false,'state','organization_membership_not_eligible');
  end if;
  select * into v_org_member from atlas.organization_memberships
  where id=p_assignee_membership_id and organization_id=v_work.organization_id;

  select pwo.farm_id into v_farm_id
  from atlas.work_execution_adapters a
  join atlas.planned_work_occurrences pwo on pwo.id=a.planned_occurrence_id
  where a.organization_id=v_work.organization_id and a.work_item_id=v_work.id and a.state='active'
  order by a.created_at limit 1;

  if v_farm_id is null then
    return jsonb_build_object('allowed',true,'state','no_farm_execution_carrier','organizationMembershipId',p_assignee_membership_id);
  end if;

  select count(*),min(fm.id) into v_count,v_farm_membership_id
  from atlas.farm_memberships fm
  where fm.farm_id=v_farm_id and fm.user_id=v_org_member.user_id
    and atlas.farm_membership_eligible_on_date_v1(fm.id,v_farm_id,p_service_date);

  return jsonb_build_object(
    'allowed',v_count=1,
    'state',case when v_count=1 then 'eligible' when v_count=0 then 'no_eligible_farm_membership' else 'ambiguous_farm_membership' end,
    'farmId',v_farm_id,
    'organizationMembershipId',p_assignee_membership_id,
    'farmMembershipId',case when v_count=1 then v_farm_membership_id else null end,
    'matchingFarmMemberships',v_count
  );
end;
$$;

create or replace function atlas.validate_work_execution_plan_v1()
returns trigger
language plpgsql security definer
set search_path='pg_catalog','atlas'
as $$
declare
  v_work atlas.work_items%rowtype;
  v_allocation atlas.work_allocations%rowtype;
  v_delivery jsonb;
begin
  select * into v_work from atlas.work_items where id=new.work_item_id;
  if v_work.id is null or v_work.organization_id<>new.organization_id then
    raise exception 'Execution plan must belong to its Company Work organization.' using errcode='23514';
  end if;
  select * into v_allocation from atlas.work_allocations where id=new.responsible_allocation_id;
  if v_allocation.id is null
     or v_allocation.organization_id<>new.organization_id
     or v_allocation.work_item_id<>new.work_item_id
     or v_allocation.assignee_membership_id<>new.assignee_membership_id
     or v_allocation.allocation_role<>'responsible' then
    raise exception 'Execution plan must point to the responsible Company Work allocation.' using errcode='23514';
  end if;
  if new.plan_state='active' then
    if v_work.work_state<>'open' or v_allocation.state<>'active' then
      raise exception 'An active execution plan requires open Work and active Responsibility.' using errcode='23514';
    end if;
    v_delivery:=atlas.company_work_execution_membership_check_v1(new.work_item_id,new.assignee_membership_id,new.planned_service_date);
    if not coalesce((v_delivery->>'allowed')::boolean,false) then
      raise exception 'The responsible person cannot receive this Work on the planned service date (%).',v_delivery->>'state' using errcode='23514';
    end if;
    v_delivery:=atlas.company_work_execution_membership_check_v1(new.work_item_id,new.assignee_membership_id,new.exposure_service_date);
    if not coalesce((v_delivery->>'allowed')::boolean,false) then
      raise exception 'The responsible person cannot receive this Work on the current exposure date (%).',v_delivery->>'state' using errcode='23514';
    end if;
  end if;
  new.updated_at:=now();
  return new;
end;
$$;

create or replace function atlas.company_work_occurrence_schedule_gate_v1(
  p_occurrence_id uuid,
  p_as_of_date date
) returns boolean
language plpgsql stable security definer
set search_path='pg_catalog','atlas'
as $$
declare
  v_work atlas.work_items%rowtype;
  v_allocation atlas.work_allocations%rowtype;
  v_plan atlas.work_execution_plans%rowtype;
  v_delivery jsonb;
begin
  select wi.* into v_work
  from atlas.work_execution_adapters a
  join atlas.work_items wi on wi.organization_id=a.organization_id and wi.id=a.work_item_id
  where a.planned_occurrence_id=p_occurrence_id and a.state='active'
    and coalesce(wi.metadata->>'managerSchedulingAuthority','')='work_execution_plans'
  order by a.created_at limit 1;
  if v_work.id is null then return true; end if;

  select * into v_allocation from atlas.work_allocations
  where organization_id=v_work.organization_id and work_item_id=v_work.id
    and state='active' and allocation_role='responsible' limit 1;
  if v_allocation.id is null then return false; end if;

  select * into v_plan from atlas.work_execution_plans
  where organization_id=v_work.organization_id and work_item_id=v_work.id and plan_state='active' limit 1;
  if v_plan.id is null
     or v_plan.responsible_allocation_id<>v_allocation.id
     or v_plan.assignee_membership_id<>v_allocation.assignee_membership_id
     or p_as_of_date<v_plan.exposure_service_date then return false; end if;

  v_delivery:=atlas.company_work_execution_membership_check_v1(v_work.id,v_plan.assignee_membership_id,v_plan.exposure_service_date);
  return coalesce((v_delivery->>'allowed')::boolean,false);
end;
$$;

create or replace function atlas.sync_company_work_execution_plan_carrier_v1(p_work_item_id uuid)
returns jsonb
language plpgsql security definer
set search_path='pg_catalog','atlas'
as $$
declare
  v_work atlas.work_items%rowtype;
  v_plan atlas.work_execution_plans%rowtype;
  v_adapter atlas.work_execution_adapters%rowtype;
  v_occ atlas.planned_work_occurrences%rowtype;
  v_task atlas.tasks%rowtype;
  v_delivery jsonb;
  v_farm_member_id uuid;
  v_placement atlas.worker_day_task_placements%rowtype;
  v_day_window text;
  v_sort_order numeric;
  v_original_not_before date;
  v_changed boolean:=false;
begin
  select * into v_work from atlas.work_items where id=p_work_item_id;
  if v_work.id is null then return jsonb_build_object('state','missing_work','workItemId',p_work_item_id); end if;
  if coalesce(v_work.metadata->>'managerSchedulingAuthority','')<>'work_execution_plans' then
    return jsonb_build_object('state','not_manager_scheduled_company_work','workItemId',v_work.id);
  end if;

  select * into v_adapter from atlas.work_execution_adapters
  where organization_id=v_work.organization_id and work_item_id=v_work.id and state='active'
  order by created_at limit 1;
  if v_adapter.id is null then return jsonb_build_object('state','no_execution_adapter','workItemId',v_work.id); end if;

  if v_adapter.planned_occurrence_id is not null then
    select * into v_occ from atlas.planned_work_occurrences where id=v_adapter.planned_occurrence_id;
  end if;
  if v_adapter.task_id is not null then select * into v_task from atlas.tasks where id=v_adapter.task_id; end if;

  select * into v_plan from atlas.work_execution_plans
  where organization_id=v_work.organization_id and work_item_id=v_work.id and plan_state='active' limit 1;

  if v_plan.id is null then
    if v_occ.id is not null then
      begin v_original_not_before:=nullif(v_occ.metadata->>'companyWorkOriginalNotBeforeDate','')::date;
      exception when others then v_original_not_before:=null; end;
      update atlas.planned_work_occurrences
      set not_before_date=coalesce(v_original_not_before,not_before_date),
          task_payload=coalesce(task_payload,'{}'::jsonb)||jsonb_build_object(
            'metadata',coalesce(task_payload->'metadata','{}'::jsonb)||jsonb_build_object(
              'company_work_schedule_state','unscheduled','company_work_schedule_authority','work_execution_plans'
            )),
          metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('companyWorkScheduleState','unscheduled'),
          updated_at=now()
      where id=v_occ.id;
    end if;
    if v_task.id is not null then
      select * into v_placement from atlas.worker_day_task_placements where task_id=v_task.id;
      if v_placement.id is not null and v_placement.state='placed' then
        insert into atlas.worker_day_task_placement_events(
          organization_id,farm_id,membership_id,task_id,placement_id,event_kind,
          from_service_date,to_service_date,from_day_window,to_day_window,from_sort_order,to_sort_order,
          actor_user_id,metadata,from_planned_occurrence_id,to_planned_occurrence_id
        ) values(
          v_placement.organization_id,v_placement.farm_id,v_placement.membership_id,v_placement.task_id,v_placement.id,'owner_returned_to_atlas',
          v_placement.service_date,null,v_placement.day_window,null,v_placement.sort_order,null,null,
          jsonb_build_object('source','company_work_execution_plan','reason','Company Work has no active manager plan.'),
          v_placement.planned_occurrence_id,null
        );
        update atlas.worker_day_task_placements set state='returned_to_atlas',placement_reason='Company Work is not currently scheduled by management.',updated_at=now() where id=v_placement.id;
      end if;
    end if;
    return jsonb_build_object('state','unscheduled','workItemId',v_work.id,'adapterId',v_adapter.id,'taskId',v_adapter.task_id);
  end if;

  v_delivery:=atlas.company_work_execution_membership_check_v1(v_work.id,v_plan.assignee_membership_id,v_plan.exposure_service_date);
  if not coalesce((v_delivery->>'allowed')::boolean,false) then
    update atlas.work_execution_plans set plan_state='needs_replan',plan_reason='Execution membership is not eligible for the current exposure day.' where id=v_plan.id;
    insert into atlas.work_execution_plan_events(
      organization_id,work_item_id,plan_id,event_kind,from_planned_service_date,to_planned_service_date,
      from_exposure_service_date,to_exposure_service_date,reason,metadata
    ) values(v_plan.organization_id,v_plan.work_item_id,v_plan.id,'needs_replan',v_plan.planned_service_date,v_plan.planned_service_date,
      v_plan.exposure_service_date,v_plan.exposure_service_date,'Execution membership is not eligible for the current exposure day.',v_delivery);
    return jsonb_build_object('state','needs_replan','workItemId',v_work.id,'planId',v_plan.id,'delivery',v_delivery);
  end if;
  v_farm_member_id:=nullif(v_delivery->>'farmMembershipId','')::uuid;

  if v_occ.id is not null then
    update atlas.planned_work_occurrences
    set not_before_date=v_plan.exposure_service_date,
        task_payload=coalesce(task_payload,'{}'::jsonb)||jsonb_build_object(
          'metadata',coalesce(task_payload->'metadata','{}'::jsonb)||jsonb_build_object(
            'company_work_schedule_state','scheduled',
            'company_work_schedule_authority','work_execution_plans',
            'company_work_execution_plan_id',v_plan.id,
            'manager_planned_service_date',v_plan.planned_service_date,
            'worker_exposure_service_date',v_plan.exposure_service_date,
            'first_manager_planned_service_date',v_plan.first_planned_service_date
          )),
        metadata=coalesce(metadata,'{}'::jsonb)||jsonb_strip_nulls(jsonb_build_object(
          'companyWorkScheduleState','scheduled',
          'companyWorkExecutionPlanId',v_plan.id,
          'companyWorkOriginalNotBeforeDate',coalesce(metadata->>'companyWorkOriginalNotBeforeDate',v_occ.not_before_date::text),
          'managerPlannedServiceDate',v_plan.planned_service_date,
          'workerExposureServiceDate',v_plan.exposure_service_date
        )),
        updated_at=now()
    where id=v_occ.id;
  end if;

  if v_task.id is null then
    return jsonb_build_object('state','scheduled_waiting_for_task_carrier','workItemId',v_work.id,'planId',v_plan.id,'occurrenceId',v_occ.id);
  end if;
  if v_task.status not in ('open','blocked') then
    return jsonb_build_object('state','task_not_open','workItemId',v_work.id,'planId',v_plan.id,'taskId',v_task.id,'taskStatus',v_task.status);
  end if;
  if v_farm_member_id is null
     or v_task.assigned_membership_id is distinct from v_farm_member_id
     or v_task.assigned_user_id is distinct from (select user_id from atlas.farm_memberships where id=v_farm_member_id) then
    return jsonb_build_object('state','task_carrier_responsibility_not_synchronized','workItemId',v_work.id,'planId',v_plan.id,'taskId',v_task.id,'delivery',v_delivery);
  end if;

  v_day_window:=atlas.worker_task_day_window_v1(v_task.action_key,v_task.task_type,v_task.metadata);
  v_sort_order:=atlas.worker_task_order_v1(v_task.action_key,v_task.task_type,v_task.metadata);
  select * into v_placement from atlas.worker_day_task_placements where task_id=v_task.id for update;

  if v_placement.id is null then
    insert into atlas.worker_day_task_placements(
      organization_id,farm_id,membership_id,task_id,service_date,day_window,sort_order,
      placement_source,placement_reason,state,owner_actor_user_id,planned_occurrence_id
    ) values(
      v_task.organization_id,v_task.farm_id,v_farm_member_id,v_task.id,v_plan.exposure_service_date,v_day_window,v_sort_order,
      'owner','Company Work manager plan.','placed',null,v_task.planned_occurrence_id
    ) returning * into v_placement;
    insert into atlas.worker_day_task_placement_events(
      organization_id,farm_id,membership_id,task_id,placement_id,event_kind,to_service_date,to_day_window,to_sort_order,
      actor_user_id,metadata,to_planned_occurrence_id
    ) values(v_placement.organization_id,v_placement.farm_id,v_placement.membership_id,v_placement.task_id,v_placement.id,'owner_added',
      v_placement.service_date,v_placement.day_window,v_placement.sort_order,null,
      jsonb_build_object('source','company_work_execution_plan','companyWorkItemId',v_work.id,'planId',v_plan.id,'plannedServiceDate',v_plan.planned_service_date,'exposureServiceDate',v_plan.exposure_service_date),
      v_placement.planned_occurrence_id);
    v_changed:=true;
  elsif v_placement.service_date is distinct from v_plan.exposure_service_date
     or v_placement.membership_id is distinct from v_farm_member_id
     or v_placement.state<>'placed' then
    insert into atlas.worker_day_task_placement_events(
      organization_id,farm_id,membership_id,task_id,placement_id,event_kind,
      from_service_date,to_service_date,from_day_window,to_day_window,from_sort_order,to_sort_order,
      actor_user_id,metadata,from_planned_occurrence_id,to_planned_occurrence_id
    ) values(v_task.organization_id,v_task.farm_id,v_farm_member_id,v_task.id,v_placement.id,'owner_rescheduled',
      v_placement.service_date,v_plan.exposure_service_date,v_placement.day_window,v_day_window,v_placement.sort_order,v_sort_order,null,
      jsonb_build_object('source','company_work_execution_plan','companyWorkItemId',v_work.id,'planId',v_plan.id,'plannedServiceDate',v_plan.planned_service_date,'exposureServiceDate',v_plan.exposure_service_date),
      v_placement.planned_occurrence_id,v_task.planned_occurrence_id);
    update atlas.worker_day_task_placements
    set membership_id=v_farm_member_id,service_date=v_plan.exposure_service_date,day_window=v_day_window,sort_order=v_sort_order,
        placement_source='owner',placement_reason='Company Work manager plan.',state='placed',planned_occurrence_id=v_task.planned_occurrence_id,updated_at=now()
    where id=v_placement.id;
    v_changed:=true;
  end if;

  if v_changed then
    insert into atlas.work_execution_plan_events(
      organization_id,work_item_id,plan_id,event_kind,to_planned_service_date,to_exposure_service_date,metadata
    ) values(v_plan.organization_id,v_plan.work_item_id,v_plan.id,'carrier_projected',v_plan.planned_service_date,v_plan.exposure_service_date,
      jsonb_build_object('taskId',v_task.id,'workerDayPlacementId',v_placement.id));
  end if;
  return jsonb_build_object('state','worker_day_projected','workItemId',v_work.id,'planId',v_plan.id,'taskId',v_task.id,'workerDayPlacementId',v_placement.id,'changed',v_changed);
end;
$$;

create or replace function atlas.reconcile_company_work_execution_plan_responsibility_v1(p_work_item_id uuid)
returns jsonb
language plpgsql security definer
set search_path='pg_catalog','atlas'
as $$
declare
  v_plan atlas.work_execution_plans%rowtype;
  v_allocation atlas.work_allocations%rowtype;
begin
  select * into v_plan from atlas.work_execution_plans
  where work_item_id=p_work_item_id and plan_state in ('active','needs_replan') limit 1 for update;
  select * into v_allocation from atlas.work_allocations
  where work_item_id=p_work_item_id and state='active' and allocation_role='responsible' limit 1;

  if v_plan.id is not null and v_plan.plan_state='active'
     and (v_allocation.id is null or v_plan.responsible_allocation_id<>v_allocation.id or v_plan.assignee_membership_id<>v_allocation.assignee_membership_id) then
    update atlas.work_execution_plans set plan_state='needs_replan',plan_reason='Responsibility changed; the old worker-day plan was preserved as history but is no longer executable.' where id=v_plan.id;
    insert into atlas.work_execution_plan_events(
      organization_id,work_item_id,plan_id,event_kind,from_planned_service_date,to_planned_service_date,
      from_exposure_service_date,to_exposure_service_date,reason,metadata
    ) values(v_plan.organization_id,v_plan.work_item_id,v_plan.id,'needs_replan',v_plan.planned_service_date,v_plan.planned_service_date,
      v_plan.exposure_service_date,v_plan.exposure_service_date,'Responsibility changed; manager re-planning is required.',
      jsonb_strip_nulls(jsonb_build_object('priorAllocationId',v_plan.responsible_allocation_id,'currentAllocationId',v_allocation.id)));
  end if;
  perform atlas.sync_company_work_execution_plan_carrier_v1(p_work_item_id);
  return jsonb_build_object('workItemId',p_work_item_id,'planId',v_plan.id,'allocationId',v_allocation.id);
end;
$$;

create or replace function atlas.reconcile_company_work_execution_plan_responsibility_trigger_v1()
returns trigger
language plpgsql security definer
set search_path='pg_catalog','atlas'
as $$ begin
  if coalesce(new.allocation_role,old.allocation_role)='responsible' then
    perform atlas.reconcile_company_work_execution_plan_responsibility_v1(coalesce(new.work_item_id,old.work_item_id));
  end if;
  return new;
end $$;

drop trigger if exists work_allocations_reconcile_execution_plan_v1 on atlas.work_allocations;
create trigger work_allocations_reconcile_execution_plan_v1
after insert or update of state,assignee_membership_id on atlas.work_allocations
for each row execute function atlas.reconcile_company_work_execution_plan_responsibility_trigger_v1();

create or replace function atlas.sync_company_work_plan_after_adapter_task_v1()
returns trigger
language plpgsql security definer
set search_path='pg_catalog','atlas'
as $$ begin
  if new.task_id is distinct from old.task_id or (tg_op='INSERT' and new.task_id is not null) then
    perform atlas.sync_company_work_execution_plan_carrier_v1(new.work_item_id);
  end if;
  return new;
end $$;

drop trigger if exists work_execution_adapters_sync_company_work_plan_v1 on atlas.work_execution_adapters;
create trigger work_execution_adapters_sync_company_work_plan_v1
after insert or update of task_id on atlas.work_execution_adapters
for each row execute function atlas.sync_company_work_plan_after_adapter_task_v1();

create or replace function atlas.carry_company_work_plan_after_elapsed_worker_day_v1()
returns trigger
language plpgsql security definer
set search_path='pg_catalog','atlas'
as $$
declare
  v_work_id uuid;
  v_plan atlas.work_execution_plans%rowtype;
  v_org_member atlas.organization_memberships%rowtype;
  v_next date;
  v_delivery jsonb;
begin
  if not (old.state='placed' and new.state='returned_to_atlas') then return new; end if;
  select a.work_item_id into v_work_id
  from atlas.work_execution_adapters a
  join atlas.work_items wi on wi.id=a.work_item_id and wi.organization_id=a.organization_id
  where a.task_id=new.task_id and a.state='active'
    and coalesce(wi.metadata->>'managerSchedulingAuthority','')='work_execution_plans'
  order by a.created_at limit 1;
  if v_work_id is null then return new; end if;
  select * into v_plan from atlas.work_execution_plans
  where work_item_id=v_work_id and plan_state='active' limit 1 for update;
  if v_plan.id is null or v_plan.exposure_service_date<>old.service_date then return new; end if;

  v_next:=atlas.next_worker_day_v1(new.farm_id,new.membership_id,old.service_date);
  if v_next is null then
    update atlas.work_execution_plans set plan_state='needs_replan',plan_reason='No next eligible Worker Day exists for automatic rollover.' where id=v_plan.id;
    insert into atlas.work_execution_plan_events(organization_id,work_item_id,plan_id,event_kind,from_planned_service_date,to_planned_service_date,from_exposure_service_date,to_exposure_service_date,reason,metadata)
    values(v_plan.organization_id,v_plan.work_item_id,v_plan.id,'needs_replan',v_plan.planned_service_date,v_plan.planned_service_date,v_plan.exposure_service_date,v_plan.exposure_service_date,'No next eligible Worker Day exists for automatic rollover.',jsonb_build_object('source','elapsed_worker_day_rollover'));
    return new;
  end if;
  v_delivery:=atlas.company_work_execution_membership_check_v1(v_work_id,v_plan.assignee_membership_id,v_next);
  if not coalesce((v_delivery->>'allowed')::boolean,false) then
    update atlas.work_execution_plans set plan_state='needs_replan',plan_reason='Worker is not eligible on the next Worker Day; manager re-planning is required.' where id=v_plan.id;
    insert into atlas.work_execution_plan_events(organization_id,work_item_id,plan_id,event_kind,from_planned_service_date,to_planned_service_date,from_exposure_service_date,to_exposure_service_date,reason,metadata)
    values(v_plan.organization_id,v_plan.work_item_id,v_plan.id,'needs_replan',v_plan.planned_service_date,v_plan.planned_service_date,v_plan.exposure_service_date,v_plan.exposure_service_date,'Worker is not eligible on the next Worker Day; manager re-planning is required.',v_delivery);
    return new;
  end if;

  update atlas.work_execution_plans
  set exposure_service_date=v_next,rollover_count=rollover_count+1,
      metadata=metadata||jsonb_build_object('lastRolloverFrom',old.service_date,'lastRolloverTo',v_next,'rolloverPreservesManagerPlan',true)
  where id=v_plan.id;
  insert into atlas.work_execution_plan_events(
    organization_id,work_item_id,plan_id,event_kind,from_planned_service_date,to_planned_service_date,
    from_exposure_service_date,to_exposure_service_date,reason,metadata
  ) values(v_plan.organization_id,v_plan.work_item_id,v_plan.id,'carried_forward',v_plan.planned_service_date,v_plan.planned_service_date,
    old.service_date,v_next,'Prior Worker Day elapsed while Work remained open; exposure carried forward without rewriting the manager plan.',
    jsonb_build_object('source','elapsed_worker_day_rollover','taskId',new.task_id));
  perform atlas.sync_company_work_execution_plan_carrier_v1(v_work_id);
  return new;
end;
$$;

drop trigger if exists worker_day_task_placements_company_work_rollover_v1 on atlas.worker_day_task_placements;
create trigger worker_day_task_placements_company_work_rollover_v1
after update of state on atlas.worker_day_task_placements
for each row execute function atlas.carry_company_work_plan_after_elapsed_worker_day_v1();

create or replace function atlas.invalidate_company_work_plans_for_membership_change_v1()
returns trigger
language plpgsql security definer
set search_path='pg_catalog','atlas'
as $$
declare v_plan record;
begin
  for v_plan in
    select p.* from atlas.work_execution_plans p
    where p.assignee_membership_id=new.id and p.plan_state='active'
      and (not atlas.organization_membership_eligible_on_date_v1(new.id,new.organization_id,p.planned_service_date)
           or not atlas.organization_membership_eligible_on_date_v1(new.id,new.organization_id,p.exposure_service_date))
    for update
  loop
    update atlas.work_execution_plans set plan_state='needs_replan',plan_reason='Membership eligibility changed; manager re-planning is required.' where id=v_plan.id;
    insert into atlas.work_execution_plan_events(organization_id,work_item_id,plan_id,event_kind,from_planned_service_date,to_planned_service_date,from_exposure_service_date,to_exposure_service_date,reason,metadata)
    values(v_plan.organization_id,v_plan.work_item_id,v_plan.id,'needs_replan',v_plan.planned_service_date,v_plan.planned_service_date,v_plan.exposure_service_date,v_plan.exposure_service_date,'Membership eligibility changed; manager re-planning is required.',jsonb_build_object('organizationMembershipId',new.id));
    perform atlas.sync_company_work_execution_plan_carrier_v1(v_plan.work_item_id);
  end loop;
  return new;
end;
$$;

drop trigger if exists organization_memberships_invalidate_work_plans_v1 on atlas.organization_memberships;
create trigger organization_memberships_invalidate_work_plans_v1
after update of active,eligibility_begins_on,eligibility_ends_on on atlas.organization_memberships
for each row when (old.active is distinct from new.active or old.eligibility_begins_on is distinct from new.eligibility_begins_on or old.eligibility_ends_on is distinct from new.eligibility_ends_on)
execute function atlas.invalidate_company_work_plans_for_membership_change_v1();

create or replace function atlas.complete_company_work_execution_plan_v1()
returns trigger
language plpgsql security definer
set search_path='pg_catalog','atlas'
as $$
declare v_plan atlas.work_execution_plans%rowtype;
begin
  if old.work_state is distinct from new.work_state and new.work_state='completed' then
    select * into v_plan from atlas.work_execution_plans where work_item_id=new.id and plan_state in ('active','needs_replan') limit 1 for update;
    if v_plan.id is not null then
      update atlas.work_execution_plans set plan_state='completed' where id=v_plan.id;
      insert into atlas.work_execution_plan_events(organization_id,work_item_id,plan_id,event_kind,from_planned_service_date,to_planned_service_date,from_exposure_service_date,to_exposure_service_date,reason,metadata)
      values(v_plan.organization_id,v_plan.work_item_id,v_plan.id,'completed',v_plan.planned_service_date,v_plan.planned_service_date,v_plan.exposure_service_date,v_plan.exposure_service_date,'Company Work completed.',jsonb_build_object('completedAt',new.completed_at));
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists work_items_complete_execution_plan_v1 on atlas.work_items;
create trigger work_items_complete_execution_plan_v1
after update of work_state on atlas.work_items
for each row execute function atlas.complete_company_work_execution_plan_v1();

create or replace function atlas.stamp_production_company_work_manager_scheduling_v1()
returns trigger
language plpgsql
set search_path='pg_catalog','atlas'
as $$ begin
  if new.source_object_type='production_bed_assignment' then
    new.metadata:=coalesce(new.metadata,'{}'::jsonb)||jsonb_build_object(
      'managerSchedulingAuthority','work_execution_plans',
      'responsibilityAndScheduleSeparate',true,
      'workerDayExposureIsProjection',true
    );
  end if;
  return new;
end $$;

drop trigger if exists work_items_stamp_production_manager_scheduling_v1 on atlas.work_items;
create trigger work_items_stamp_production_manager_scheduling_v1
before insert or update on atlas.work_items
for each row execute function atlas.stamp_production_company_work_manager_scheduling_v1();

update atlas.work_items
set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
  'managerSchedulingAuthority','work_execution_plans',
  'responsibilityAndScheduleSeparate',true,
  'workerDayExposureIsProjection',true
),updated_at=now()
where source_object_type='production_bed_assignment';

create or replace function atlas.work_occurrence_gate_satisfied_v1(p_occurrence_id uuid, p_as_of_date date)
returns boolean
language sql stable security definer
set search_path='pg_catalog','atlas'
as $$
  select case
    when occurrence.id is null then false
    when not atlas.company_work_occurrence_schedule_gate_v1(occurrence.id,p_as_of_date) then false
    when nullif(occurrence.task_payload->>'assigned_membership_id','') is not null
      and not exists(
        select 1 from atlas.farm_memberships explicit_member
        where explicit_member.id::text=occurrence.task_payload->>'assigned_membership_id'
          and explicit_member.farm_id=occurrence.farm_id
          and explicit_member.active
      ) then false
    when exists(
      select 1
      from atlas.work_execution_adapters adapter
      join atlas.work_items work_item on work_item.organization_id=adapter.organization_id and work_item.id=adapter.work_item_id
      where adapter.planned_occurrence_id=occurrence.id and adapter.state='active' and work_item.work_state='open'
        and coalesce(adapter.metadata->>'responsibilityAuthority','')='work_allocations'
    ) and not exists(
      select 1
      from atlas.work_execution_adapters adapter
      join atlas.work_items work_item on work_item.organization_id=adapter.organization_id and work_item.id=adapter.work_item_id
      join atlas.work_allocations allocation on allocation.organization_id=work_item.organization_id and allocation.work_item_id=work_item.id
        and allocation.state='active' and allocation.allocation_role='responsible'
      join atlas.organization_memberships org_member on org_member.organization_id=allocation.organization_id and org_member.id=allocation.assignee_membership_id and org_member.active
      join atlas.farm_memberships farm_member on farm_member.farm_id=occurrence.farm_id and farm_member.user_id=org_member.user_id and farm_member.active
      where adapter.planned_occurrence_id=occurrence.id and adapter.state='active' and work_item.work_state='open'
        and coalesce(adapter.metadata->>'responsibilityAuthority','')='work_allocations'
        and nullif(occurrence.task_payload->>'assigned_membership_id','')::uuid=farm_member.id
        and nullif(occurrence.task_payload->>'assigned_user_id','')::uuid=org_member.user_id
    ) then false
    when exists(
      select 1 from atlas.task_external_readiness_gates external_gate
      join atlas.tasks external_task on external_task.id=external_gate.task_id
      where external_task.planned_occurrence_id=occurrence.id and external_gate.gate_state='waiting'
    ) then false
    when exists(select 1 from atlas.task_release_queue_items qi where qi.planned_occurrence_id=occurrence.id and qi.state='queued') then exists(
      select 1 from atlas.task_release_queue_items qi
      where qi.planned_occurrence_id=occurrence.id and qi.state='queued'
        and not exists(select 1 from atlas.task_release_queue_items active_item where active_item.farm_id=qi.farm_id and active_item.queue_key=qi.queue_key and active_item.state='active')
        and qi.position=(select min(head.position) from atlas.task_release_queue_items head where head.farm_id=qi.farm_id and head.queue_key=qi.queue_key and head.state='queued')
        and (occurrence.not_before_date is null or occurrence.not_before_date<=p_as_of_date)
    )
    when coalesce(occurrence.task_payload->>'action_key','')='weed'
      and exists(select 1 from atlas.farm_memberships anna where anna.id=nullif(occurrence.task_payload->>'assigned_membership_id','')::uuid and anna.farm_id=occurrence.farm_id and anna.worker_key='anna' and anna.active=true)
      and exists(select 1 from atlas.task_release_queue_items qi where qi.farm_id=occurrence.farm_id and qi.queue_key='anna_weeding_rotation' and qi.state in ('active','queued'))
      and not exists(select 1 from atlas.task_release_queue_items qi where qi.planned_occurrence_id=occurrence.id and qi.queue_key='anna_weeding_rotation' and qi.state='active')
    then false
    when occurrence.state='eligible' then true
    when policy.gate_type in ('immediate','time_window','serial_queue') then occurrence.not_before_date is null or occurrence.not_before_date<=p_as_of_date
    when policy.gate_type='predecessor' then occurrence.gate_satisfied_at is not null or (
      occurrence.parent_occurrence_id is not null and exists(
        select 1 from atlas.planned_work_occurrences parent where parent.id=occurrence.parent_occurrence_id and parent.state in ('released','completed')
      )
    )
    else occurrence.gate_satisfied_at is not null
  end
  from atlas.planned_work_occurrences occurrence
  join atlas.work_release_policies policy on policy.id=occurrence.release_policy_id
  where occurrence.id=p_occurrence_id
$$;

create or replace function atlas.worker_self_day_bundle_api_v1(p_farm_id uuid,p_membership_id uuid,p_day date)
returns jsonb
language plpgsql stable security definer
set search_path='pg_catalog','atlas','auth'
as $$
declare
  v_timezone text:='America/Chicago';
  v_today date;
  v_plan jsonb;
  v_task_ids uuid[]:=array[]::uuid[];
  v_cards jsonb:='[]'::jsonb;
  v_safe_cards jsonb:='[]'::jsonb;
begin
  if auth.uid() is null then raise exception 'Authenticated user required.' using errcode='42501'; end if;
  if p_day is null then raise exception 'A worker day is required.' using errcode='22023'; end if;
  if not exists(select 1 from atlas.farm_memberships m where m.id=p_membership_id and m.farm_id=p_farm_id and m.user_id=auth.uid() and m.active=true and m.role='farm_hand') then
    raise exception 'The Farm Hand Worker Day bundle may only be read by that active Farm Hand.' using errcode='42501';
  end if;
  select coalesce(nullif(f.metadata->>'timezone',''),'America/Chicago') into v_timezone from atlas.farms f where f.id=p_farm_id;
  if not exists(select 1 from pg_timezone_names where name=v_timezone) then v_timezone:='America/Chicago'; end if;
  v_today:=(now() at time zone v_timezone)::date;
  if p_day>v_today then
    return jsonb_build_object(
      'contractVersion','worker_self_day_bundle_today_only_v1',
      'plan',jsonb_build_object('serviceDate',p_day,'realWork','[]'::jsonb,'automaticWork','[]'::jsonb,'futureWorkHidden',true),
      'taskCards','[]'::jsonb,
      'trustBoundary',jsonb_build_object('workerFutureScheduleHidden',true,'managerWeekPlanUnaffected',true)
    );
  end if;
  if p_day=v_today then
    v_plan:=atlas.worker_day_feed_plan_live_v1(p_farm_id,p_membership_id,p_day)
      ||jsonb_build_object('deferredWork','[]'::jsonb,'nextUp','[]'::jsonb,'clockTimeline',jsonb_build_object('items','[]'::jsonb),'nextUpContractVersion','worker_self_next_up_deferred_v1','contractVersion','worker_self_day_plan_fast_v1');
  else
    v_plan:=atlas.worker_self_day_plan_api_v1(p_farm_id,p_membership_id,p_day);
  end if;
  select coalesce(array_agg(distinct x.task_id) filter(where x.task_id is not null),array[]::uuid[]) into v_task_ids
  from (select nullif(row->>'taskId','')::uuid task_id from jsonb_array_elements(coalesce(v_plan->'realWork','[]'::jsonb)||coalesce(v_plan->'automaticWork','[]'::jsonb)) row) x;
  v_cards:=atlas.worker_day_operational_task_cards_v3(p_farm_id,p_membership_id,p_day,v_task_ids);
  select coalesce(jsonb_agg(card-'move_context' order by ord),'[]'::jsonb) into v_safe_cards
  from jsonb_array_elements(v_cards) with ordinality as cards(card,ord);
  return jsonb_build_object('contractVersion','worker_self_day_bundle_presentability_v1','plan',v_plan,'taskCards',v_safe_cards);
end;
$$;

revoke execute on function atlas.worker_self_day_plan_api_v1(uuid,uuid,date) from authenticated;
