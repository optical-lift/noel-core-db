begin;

create or replace function atlas.worker_production_pot_up_contract_self_api_v1(
  p_delivery_membership_id uuid,
  p_projection_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_farm_id uuid;
  v_context jsonb;
  v_projection atlas.worker_week_projection%rowtype;
  v_work_id uuid;
  v_work atlas.work_items%rowtype;
  v_adapter atlas.work_execution_adapters%rowtype;
  v_task atlas.tasks%rowtype;
  v_outputs jsonb;
begin
  if auth.uid() is null then raise exception 'Authenticated employee required.' using errcode='42501'; end if;
  select fm.farm_id into v_farm_id from atlas.farm_memberships fm where fm.id=p_delivery_membership_id;
  if v_farm_id is null then raise exception 'Worker delivery membership was not found.' using errcode='P0002'; end if;

  v_context:=atlas.organization_employee_worker_context_self_v1(v_farm_id,p_delivery_membership_id);
  if not coalesce((v_context->>'ok')::boolean,false) then
    raise exception 'Employee Worker Day authority required: %',coalesce(v_context->>'reason','unknown') using errcode='42501';
  end if;

  select * into v_projection
  from atlas.worker_week_projection p
  where p.id=p_projection_id
    and p.membership_id=p_delivery_membership_id
    and p.organization_id=(v_context->>'organizationId')::uuid
    and p.organization_membership_id=(v_context->>'organizationMembershipId')::uuid;
  if v_projection.id is null then raise exception 'Worker Day projection does not belong to this employee relationship.' using errcode='42501'; end if;

  select s.work_item_id into v_work_id
  from atlas.worker_week_projection_sources s
  where s.projection_id=v_projection.id and s.source_role='required';
  if v_work_id is null or (select count(*) from atlas.worker_week_projection_sources s where s.projection_id=v_projection.id and s.source_role='required')<>1 then
    raise exception 'Structured pot-up requires exactly one required Company Work identity.' using errcode='23514';
  end if;

  select * into v_work from atlas.work_items w
  where w.id=v_work_id
    and w.organization_id=(v_context->>'organizationId')::uuid
    and w.organization_unit_id=(v_context->>'organizationUnitId')::uuid
    and w.work_state='open'
    and w.result_contract_key='production_pot_up_v1';
  if v_work.id is null then raise exception 'This Worker Day item is not open governed production pot-up work.' using errcode='23514'; end if;

  if not exists(
    select 1 from atlas.work_allocations a
    where a.organization_id=v_work.organization_id and a.work_item_id=v_work.id
      and a.state='active' and a.allocation_role='responsible'
      and a.assignee_membership_id=(v_context->>'organizationMembershipId')::uuid
  ) then raise exception 'Current delegated Responsibility is required.' using errcode='23514'; end if;

  select * into v_adapter
  from atlas.work_execution_adapters a
  where a.organization_id=v_work.organization_id and a.work_item_id=v_work.id
    and a.state='active' and a.task_id is not null
  order by a.created_at desc limit 1;
  if v_adapter.id is null then raise exception 'Pot-up execution carrier is not materialized.' using errcode='23514'; end if;

  select * into v_task from atlas.tasks t
  where t.id=v_adapter.task_id and t.farm_id=v_farm_id
    and t.assigned_membership_id=p_delivery_membership_id
    and t.status in ('open','blocked');
  if v_task.id is null then raise exception 'Pot-up execution task does not belong to the routed employee.' using errcode='42501'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'cropCycleId',c.id,
    'cropLabel',coalesce(nullif(c.crop_label,''),nullif(c.variety,''),'Crop'),
    'containerKind',v_task.metadata->>'output_container_kind'
  ) order by c.crop_label,c.id),'[]'::jsonb)
  into v_outputs
  from atlas.task_crop_cycles tc
  join atlas.crop_cycles c on c.id=tc.crop_cycle_id
  where tc.task_id=v_task.id and tc.role in ('preserves','affects');

  if jsonb_array_length(v_outputs)=0 then raise exception 'Pot-up task has no governed crop-cycle outputs.' using errcode='23514'; end if;

  return jsonb_build_object(
    'ok',true,
    'status','pot_up_contract',
    'projectionId',v_projection.id,
    'taskId',v_task.id,
    'workItemId',v_work.id,
    'instruction',coalesce(v_task.metadata->'output_inventory_capture'->>'instruction','Record every physical output tray and its actual living plant count.'),
    'captureEachContainerSeparately',true,
    'outputs',v_outputs
  );
end;
$function$;

revoke all on function atlas.worker_production_pot_up_contract_self_api_v1(uuid,uuid) from public,anon;
grant execute on function atlas.worker_production_pot_up_contract_self_api_v1(uuid,uuid) to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,evidence,anonymous_execute_expected
) values(
  'atlas.worker_production_pot_up_contract_self_api_v1(uuid, uuid)',
  'app_endpoint','verified','active',true,true,true,1,1,
  jsonb_build_object(
    'source','atlas_worker_pot_up_contract_read_v1',
    'purpose','Expose the safe physical-output fields required to finish the employee current pot-up work.',
    'truthBoundary','Returns only the current worker exact governed pot-up carrier after employee access, unit, Responsibility, and projection checks.',
    'classificationRuleVersion',3
  ),false
)
on conflict(signature) do update set
  classification=excluded.classification,confidence=excluded.confidence,review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,evidence=excluded.evidence,
  anonymous_execute_expected=excluded.anonymous_execute_expected,reviewed_at=now();

commit;
