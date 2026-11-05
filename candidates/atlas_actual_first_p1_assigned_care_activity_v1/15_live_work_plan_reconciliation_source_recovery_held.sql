-- HELD P1: restore both exact private LIVE Work-plan reconciliation functions
-- in disposable RiverSong PG17 only. The retained old schema clone contains
-- allocation/plan triggers invoking this source but omitted the functions.
-- Source: 2026-11-05 READ-ONLY pg_get_functiondef + pg_proc.proacl in Noel.
-- No production changes, no release approvals, no invented schedule carriers.
DO $pre$
BEGIN
 IF to_regprocedure('atlas.sync_company_work_execution_plan_carrier_v1(uuid)') IS NOT NULL OR to_regprocedure('atlas.reconcile_company_work_execution_plan_responsibility_v1(uuid)') IS NOT NULL
 THEN RAISE EXCEPTION 'STOP prior private plan reconciler source present; reconcile, do not override';
 END IF;
 IF to_regclass('atlas.work_execution_adapters') IS NULL THEN RAISE EXCEPTION 'STOP live plan source dependency atlas.work_execution_adapters absent'; END IF;
 IF to_regclass('atlas.planned_work_occurrences') IS NULL THEN RAISE EXCEPTION 'STOP live plan source dependency atlas.planned_work_occurrences absent'; END IF;
 IF to_regclass('atlas.worker_day_task_placements') IS NULL THEN RAISE EXCEPTION 'STOP live plan source dependency atlas.worker_day_task_placements absent'; END IF;
 IF to_regclass('atlas.worker_day_task_placement_events') IS NULL THEN RAISE EXCEPTION 'STOP live plan source dependency atlas.worker_day_task_placement_events absent'; END IF;
 IF to_regclass('atlas.work_execution_plans') IS NULL THEN RAISE EXCEPTION 'STOP live plan source dependency atlas.work_execution_plans absent'; END IF;
 IF to_regclass('atlas.work_execution_plan_events') IS NULL THEN RAISE EXCEPTION 'STOP live plan source dependency atlas.work_execution_plan_events absent'; END IF;
END;$pre$;

CREATE OR REPLACE FUNCTION atlas.sync_company_work_execution_plan_carrier_v1(p_work_item_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION atlas.reconcile_company_work_execution_plan_responsibility_v1(p_work_item_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_plan atlas.work_execution_plans%rowtype;
  v_allocation atlas.work_allocations%rowtype;
begin
  select * into v_plan from atlas.work_execution_plans
  where work_item_id=p_work_item_id and plan_state in ('active','needs_replan') limit 1 for update;
  select * into v_allocation from atlas.work_allocations
  where work_item_id=p_work_item_id and state='active' and allocation_role='responsible' limit 1;

  if v_plan.id is not null and v_plan.plan_state='active'
     and (v_allocation.id is null or v_plan.responsible_allocation_id is distinct from v_allocation.id or v_plan.assignee_membership_id is distinct from v_allocation.assignee_membership_id) then
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
$function$;

REVOKE ALL ON FUNCTION atlas.sync_company_work_execution_plan_carrier_v1(uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION atlas.reconcile_company_work_execution_plan_responsibility_v1(uuid) FROM PUBLIC,anon,authenticated,service_role;
DO $post$
BEGIN
 IF has_function_privilege('authenticated','atlas.sync_company_work_execution_plan_carrier_v1(uuid)','EXECUTE')
 OR has_function_privilege('authenticated','atlas.reconcile_company_work_execution_plan_responsibility_v1(uuid)','EXECUTE')
 OR has_function_privilege('anon','atlas.sync_company_work_execution_plan_carrier_v1(uuid)','EXECUTE')
 OR has_function_privilege('anon','atlas.reconcile_company_work_execution_plan_responsibility_v1(uuid)','EXECUTE')
 OR NOT (SELECT prosecdef FROM pg_proc WHERE oid='atlas.sync_company_work_execution_plan_carrier_v1(uuid)'::regprocedure)
 OR NOT (SELECT prosecdef FROM pg_proc WHERE oid='atlas.reconcile_company_work_execution_plan_responsibility_v1(uuid)'::regprocedure)
 THEN RAISE EXCEPTION 'STOP private plan/source authority changed';
 END IF;
 RAISE NOTICE 'PASS exact private live plan carrier and allocation-responsibility reconciliation';
END;$post$;
