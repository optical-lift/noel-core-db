-- HELD 2026-11-05: exact live post-assignment plan reconciliation source.
-- Read-only pg_get_functiondef inspected; source missing from RiverSong's
-- protected old clone, though the existing responsibility trigger calls it.
-- Restore only inside fresh disposable PG17; never change trigger/policies.
DO $pre$
BEGIN
 IF to_regprocedure('atlas.reconcile_company_work_execution_plan_responsibility_v1(uuid)') IS NOT NULL OR
 to_regprocedure('atlas.sync_company_work_execution_plan_carrier_v1(uuid)') IS NULL
 THEN RAISE EXCEPTION 'STOP plan reconciliation already present or exact downstream source missing';
 END IF;
END;$pre$;
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
REVOKE ALL ON FUNCTION atlas.reconcile_company_work_execution_plan_responsibility_v1(uuid) FROM PUBLIC,anon,authenticated,service_role;
DO $post$
BEGIN
 IF has_function_privilege('authenticated','atlas.reconcile_company_work_execution_plan_responsibility_v1(uuid)','EXECUTE') OR
 has_function_privilege('anon','atlas.reconcile_company_work_execution_plan_responsibility_v1(uuid)','EXECUTE') OR
 NOT (SELECT prosecdef FROM pg_proc WHERE oid='atlas.reconcile_company_work_execution_plan_responsibility_v1(uuid)'::regprocedure)
 THEN RAISE EXCEPTION 'STOP preserved private plan reconciliation authority changed';
 END IF;
 RAISE NOTICE 'PASS exact private source reconciles responsibility and plan without bypass';
END;$post$;
