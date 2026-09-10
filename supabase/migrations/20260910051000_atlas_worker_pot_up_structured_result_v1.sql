begin;

create or replace function atlas.accept_company_work_pot_up_domain_result_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_adapter atlas.work_execution_adapters%rowtype;
  v_work atlas.work_items%rowtype;
  v_allocation atlas.work_allocations%rowtype;
  v_org_member atlas.organization_memberships%rowtype;
  v_farm_member atlas.farm_memberships%rowtype;
  v_expected_count integer;
  v_event_count integer;
  v_physical_count integer;
  v_physical_invalid integer;
  v_result atlas.work_execution_results%rowtype;
  v_key text;
  v_payload jsonb;
begin
  if old.status is not distinct from new.status or new.status<>'done' then return new; end if;

  select * into v_adapter
  from atlas.work_execution_adapters a
  where a.task_id=new.id and a.state='active'
  order by a.created_at desc limit 1;
  if v_adapter.id is null then return new; end if;

  select * into v_work
  from atlas.work_items w
  where w.id=v_adapter.work_item_id
    and w.organization_id=v_adapter.organization_id
    and w.work_state='open'
    and w.result_contract_key='production_pot_up_v1';
  if v_work.id is null then return new; end if;

  if lower(coalesce(new.action_key,''))<>'pot_up' and lower(coalesce(new.task_type,''))<>'pot_up' then
    raise exception 'Production pot-up Company Work can only close from a pot-up execution carrier.' using errcode='23514';
  end if;

  select * into v_allocation
  from atlas.work_allocations a
  where a.organization_id=v_work.organization_id
    and a.work_item_id=v_work.id
    and a.state='active'
    and a.allocation_role='responsible'
  limit 1;
  if v_allocation.id is null then
    raise exception 'Production pot-up completion requires active delegated Responsibility.' using errcode='23514';
  end if;

  select * into v_org_member
  from atlas.organization_memberships om
  where om.id=v_allocation.assignee_membership_id
    and om.organization_id=v_work.organization_id and om.active;
  select * into v_farm_member
  from atlas.farm_memberships fm
  where fm.id=new.assigned_membership_id and fm.farm_id=new.farm_id and fm.active;

  if v_org_member.id is null or v_farm_member.id is null
     or v_org_member.user_id is distinct from v_farm_member.user_id
     or auth.uid() is null or auth.uid() is distinct from v_org_member.user_id then
    raise exception 'Production pot-up result actor must be the currently responsible signed-in worker.' using errcode='42501';
  end if;

  select count(distinct tc.crop_cycle_id)::integer into v_expected_count
  from atlas.task_crop_cycles tc
  join atlas.production_lot_crop_cycles plc on plc.crop_cycle_id=tc.crop_cycle_id and plc.relation_role='primary'
  join atlas.production_lots pl on pl.id=plc.production_lot_id and pl.lifecycle_status='active'
  where tc.task_id=new.id and tc.role in ('preserves','affects');

  select count(distinct e.crop_cycle_id)::integer into v_event_count
  from atlas.production_lot_events e
  join atlas.production_tray_batches b on b.id=e.tray_batch_id
  where e.task_id=new.id and e.event_type='pot_up_completed'
    and e.crop_cycle_id is not null and b.source_task_id=new.id
    and b.current_quantity is not null and b.current_quantity>0;

  if jsonb_typeof(new.metadata->'pot_up_physical_outputs')<>'array' then
    raise exception 'Pot-up completion requires physical tray output evidence.' using errcode='23514';
  end if;

  select count(*)::integer into v_physical_count
  from jsonb_array_elements(new.metadata->'pot_up_physical_outputs') x
  where nullif(x->>'cropCycleId','') is not null;

  select count(*)::integer into v_physical_invalid
  from atlas.production_tray_batches b
  where b.source_task_id=new.id
    and not exists(
      select 1
      from jsonb_array_elements(new.metadata->'pot_up_physical_outputs') g
      where g->>'cropCycleId'=b.crop_cycle_id::text
        and jsonb_typeof(g->'physicalTrays')='array'
        and jsonb_array_length(g->'physicalTrays')=b.tray_count::integer
        and (
          select count(distinct (t->>'trayNumber')::integer)
          from jsonb_array_elements(g->'physicalTrays') t
        )=jsonb_array_length(g->'physicalTrays')
        and (
          select sum((t->>'livingPlants')::numeric)
          from jsonb_array_elements(g->'physicalTrays') t
        )=b.current_quantity
    );

  if coalesce(v_expected_count,0)=0
     or v_event_count<>v_expected_count
     or v_physical_count<>v_expected_count
     or v_physical_invalid<>0 then
    raise exception 'Pot-up completion evidence is incomplete or inconsistent (% crop cycles expected, % domain events, % physical output groups, % invalid batches).',v_expected_count,v_event_count,v_physical_count,v_physical_invalid using errcode='23514';
  end if;

  v_key:='production-pot-up-domain:'||new.id::text;
  v_payload:=jsonb_build_object(
    'taskId',new.id,
    'plannedOccurrenceId',new.planned_occurrence_id,
    'physicalOutputs',new.metadata->'pot_up_physical_outputs',
    'productionEvents',(
      select coalesce(jsonb_agg(jsonb_build_object(
        'eventId',e.id,'cropCycleId',e.crop_cycle_id,'productionLotId',e.production_lot_id,
        'trayBatchId',e.tray_batch_id,'eventDate',e.event_date,'livingPlants',e.quantity,'unit',e.unit
      ) order by e.crop_cycle_id),'[]'::jsonb)
      from atlas.production_lot_events e
      where e.task_id=new.id and e.event_type='pot_up_completed'
    ),
    'trayBatches',(
      select coalesce(jsonb_agg(jsonb_build_object(
        'trayBatchId',b.id,'cropCycleId',b.crop_cycle_id,'containerKind',b.container_kind,
        'trayCount',b.tray_count,'livingPlants',b.current_quantity
      ) order by b.crop_cycle_id),'[]'::jsonb)
      from atlas.production_tray_batches b where b.source_task_id=new.id
    )
  );

  insert into atlas.work_execution_results(
    organization_id,work_item_id,responsible_allocation_id,task_id,
    reported_by_user_id,reported_by_farm_membership_id,reported_by_organization_membership_id,
    result_kind,result_contract_key,idempotency_key,payload,metadata
  ) values(
    v_work.organization_id,v_work.id,v_allocation.id,new.id,
    auth.uid(),v_farm_member.id,v_org_member.id,
    'completed','production_pot_up_v1',v_key,v_payload,
    jsonb_build_object(
      'source','accept_company_work_pot_up_domain_result_v1',
      'domainEvidence','production_lot_events+production_tray_batches+physical_tray_attestation',
      'delegatedResponsibility',true
    )
  ) on conflict(organization_id,idempotency_key) do nothing;

  select * into v_result
  from atlas.work_execution_results r
  where r.organization_id=v_work.organization_id and r.idempotency_key=v_key;

  if v_result.work_item_id is distinct from v_work.id or v_result.task_id is distinct from new.id then
    raise exception 'Production pot-up result idempotency collision.' using errcode='23505';
  end if;

  insert into atlas.work_result_acceptances(
    organization_id,work_item_id,execution_result_id,decision,acceptance_kind,
    accepted_by_domain,evidence,metadata
  ) values(
    v_work.organization_id,v_work.id,v_result.id,'accepted','production_domain_adapter','production',
    jsonb_build_object(
      'resultContractKey','production_pot_up_v1',
      'responsibleAllocationId',v_allocation.id,
      'reportedByOrganizationMembershipId',v_org_member.id,
      'productionEvidenceComplete',true,
      'physicalTrayEvidenceComplete',true
    ),
    jsonb_build_object(
      'source','accept_company_work_pot_up_domain_result_v1',
      'managerApprovalRequired',false
    )
  ) on conflict(execution_result_id) do nothing;

  update atlas.work_items
  set work_state='completed',completed_at=coalesce(completed_at,new.completed_at,now()),updated_at=now()
  where id=v_work.id and work_state='open';

  update atlas.work_allocations
  set state='completed',completed_at=coalesce(completed_at,new.completed_at,now()),updated_at=now()
  where id=v_allocation.id and state='active';

  update atlas.work_execution_adapters
  set state='completed',completed_at=coalesce(completed_at,new.completed_at,now()),updated_at=now()
  where id=v_adapter.id and state='active';

  return new;
end;
$function$;

drop trigger if exists aa0_accept_company_work_pot_up_domain_result_v1 on atlas.tasks;
create trigger aa0_accept_company_work_pot_up_domain_result_v1
after update of status on atlas.tasks
for each row
when (new.status='done' and old.status is distinct from new.status)
execute function atlas.accept_company_work_pot_up_domain_result_v1();

create or replace function atlas.worker_record_production_pot_up_self_api_v1(
  p_delivery_membership_id uuid,
  p_projection_id uuid,
  p_outputs jsonb,
  p_care_date date default null,
  p_note text default null,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_uid uuid:=auth.uid();
  v_farm_id uuid;
  v_context jsonb;
  v_projection atlas.worker_week_projection%rowtype;
  v_work_ids uuid[];
  v_work atlas.work_items%rowtype;
  v_allocation atlas.work_allocations%rowtype;
  v_plan atlas.work_execution_plans%rowtype;
  v_adapter atlas.work_execution_adapters%rowtype;
  v_task atlas.tasks%rowtype;
  v_group jsonb;
  v_tray jsonb;
  v_cycle_id uuid;
  v_tray_number integer;
  v_living numeric;
  v_group_living numeric;
  v_seen integer[];
  v_aggregate jsonb:='[]'::jsonb;
  v_normalized jsonb:='[]'::jsonb;
  v_domain jsonb;
  v_result atlas.work_execution_results%rowtype;
  v_acceptance atlas.work_result_acceptances%rowtype;
  v_key text:=coalesce(nullif(btrim(coalesce(p_idempotency_key,'')),''),'employee-pot-up:'||p_projection_id::text||':'||clock_timestamp()::text);
begin
  if v_uid is null then raise exception 'Authenticated employee required.' using errcode='42501'; end if;
  if p_delivery_membership_id is null or p_projection_id is null then raise exception 'Worker Day context is required.' using errcode='22023'; end if;
  if jsonb_typeof(p_outputs)<>'array' or jsonb_array_length(p_outputs)=0 then raise exception 'Pot-up output must contain at least one crop-cycle result.' using errcode='22023'; end if;
  if length(v_key)>160 then raise exception 'Pot-up idempotency key is too long.' using errcode='22023'; end if;

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

  select array_agg(s.work_item_id order by s.work_item_id) into v_work_ids
  from atlas.worker_week_projection_sources s
  where s.projection_id=v_projection.id and s.source_role='required';
  if coalesce(array_length(v_work_ids,1),0)<>1 then raise exception 'Structured pot-up requires exactly one required Company Work identity.' using errcode='23514'; end if;

  select * into v_work from atlas.work_items w
  where w.id=v_work_ids[1]
    and w.organization_id=(v_context->>'organizationId')::uuid
    and w.organization_unit_id=(v_context->>'organizationUnitId')::uuid
    and w.work_state='open'
    and w.result_contract_key='production_pot_up_v1';
  if v_work.id is null then raise exception 'This Worker Day item is not open governed production pot-up work.' using errcode='23514'; end if;

  select * into v_allocation from atlas.work_allocations a
  where a.organization_id=v_work.organization_id and a.work_item_id=v_work.id
    and a.state='active' and a.allocation_role='responsible'
    and a.assignee_membership_id=(v_context->>'organizationMembershipId')::uuid
  limit 1;
  if v_allocation.id is null then raise exception 'Current delegated Responsibility is required.' using errcode='23514'; end if;

  select * into v_plan from atlas.work_execution_plans p
  where p.organization_id=v_work.organization_id and p.work_item_id=v_work.id
    and p.plan_state='active' and p.responsible_allocation_id=v_allocation.id
    and p.assignee_membership_id=(v_context->>'organizationMembershipId')::uuid
    and p.exposure_service_date=(v_context->>'serviceDate')::date
  limit 1;
  if v_plan.id is null then raise exception 'Pot-up may only be returned from the currently exposed governed Worker Day.' using errcode='23514'; end if;

  select * into v_adapter from atlas.work_execution_adapters a
  where a.organization_id=v_work.organization_id and a.work_item_id=v_work.id
    and a.state='active' and a.task_id is not null
  order by a.created_at desc limit 1;
  if v_adapter.id is null then raise exception 'Pot-up execution carrier is not materialized.' using errcode='23514'; end if;

  select * into v_task from atlas.tasks t
  where t.id=v_adapter.task_id and t.farm_id=v_farm_id
    and t.assigned_membership_id=p_delivery_membership_id
    and t.status in ('open','blocked');
  if v_task.id is null then raise exception 'Pot-up execution task does not belong to the routed employee.' using errcode='42501'; end if;
  if lower(coalesce(v_task.action_key,''))<>'pot_up' and lower(coalesce(v_task.task_type,''))<>'pot_up' then raise exception 'Execution task is not pot-up.' using errcode='23514'; end if;

  for v_group in select value from jsonb_array_elements(p_outputs)
  loop
    begin v_cycle_id:=(v_group->>'cropCycleId')::uuid; exception when others then raise exception 'Each output requires a valid cropCycleId.' using errcode='22023'; end;
    if jsonb_typeof(v_group->'physicalTrays')<>'array' or jsonb_array_length(v_group->'physicalTrays')=0 then raise exception 'Each crop cycle requires at least one physical output tray.' using errcode='22023'; end if;
    v_group_living:=0; v_seen:=array[]::integer[];
    for v_tray in select value from jsonb_array_elements(v_group->'physicalTrays')
    loop
      begin v_tray_number:=(v_tray->>'trayNumber')::integer; v_living:=(v_tray->>'livingPlants')::numeric; exception when others then raise exception 'Each physical tray requires numeric trayNumber and livingPlants.' using errcode='22023'; end;
      if v_tray_number<=0 or v_living<=0 then raise exception 'Tray number and living plant count must be positive.' using errcode='22023'; end if;
      if v_tray_number=any(v_seen) then raise exception 'Physical tray numbers must be unique within a crop cycle.' using errcode='22023'; end if;
      v_seen:=array_append(v_seen,v_tray_number); v_group_living:=v_group_living+v_living;
    end loop;
    v_normalized:=v_normalized||jsonb_build_array(jsonb_build_object('cropCycleId',v_cycle_id,'containerKind',coalesce(nullif(btrim(v_group->>'containerKind'),''),v_task.metadata->>'output_container_kind'),'physicalTrays',v_group->'physicalTrays'));
    v_aggregate:=v_aggregate||jsonb_build_array(jsonb_build_object('cropCycleId',v_cycle_id,'livingPlants',v_group_living,'trayCount',jsonb_array_length(v_group->'physicalTrays'),'containerKind',coalesce(nullif(btrim(v_group->>'containerKind'),''),v_task.metadata->>'output_container_kind')));
  end loop;

  update atlas.tasks set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('pot_up_physical_outputs',v_normalized,'pot_up_structured_result_source','worker_record_production_pot_up_self_api_v1'),updated_at=now() where id=v_task.id;

  v_domain:=atlas.record_production_pot_up_v1(v_task.id,v_aggregate,coalesce(p_care_date,(v_context->>'serviceDate')::date),p_note,v_key);

  update atlas.production_tray_batches b
  set metadata=coalesce(b.metadata,'{}'::jsonb)||jsonb_build_object('physical_trays',g.value->'physicalTrays','physical_trays_recorded_by',v_uid),updated_at=now()
  from jsonb_array_elements(v_normalized) g(value)
  where b.source_task_id=v_task.id and b.crop_cycle_id=(g.value->>'cropCycleId')::uuid;

  select * into v_result from atlas.work_execution_results r
  where r.organization_id=v_work.organization_id and r.work_item_id=v_work.id
    and r.task_id=v_task.id and r.result_contract_key='production_pot_up_v1'
  order by r.reported_at desc limit 1;
  select * into v_acceptance from atlas.work_result_acceptances a where a.execution_result_id=v_result.id;
  select * into v_work from atlas.work_items w where w.id=v_work.id;

  if v_result.id is null or v_acceptance.decision<>'accepted' or v_work.work_state<>'completed' then
    raise exception 'Pot-up domain result did not close Company Work atomically.' using errcode='55000';
  end if;

  if exists(select 1 from atlas.worker_delivery_pilot_active_attention a where a.delivery_membership_id=p_delivery_membership_id and a.projection_id=p_projection_id) then
    insert into atlas.worker_delivery_pilot_events(organization_id,organization_membership_id,delivery_membership_id,projection_id,session_id,actor_user_id,event_kind,effective_at,metadata)
    values(v_work.organization_id,(v_context->>'organizationMembershipId')::uuid,p_delivery_membership_id,p_projection_id,null,v_uid,'stop',clock_timestamp(),jsonb_build_object('source','structured_pot_up_completion','employeeSeatId',v_context->>'employeeSeatId'));
    delete from atlas.worker_delivery_pilot_active_attention where delivery_membership_id=p_delivery_membership_id and projection_id=p_projection_id;
  end if;

  return jsonb_build_object('ok',true,'status','pot_up_completed','projectionId',p_projection_id,'taskId',v_task.id,'workItemId',v_work.id,'executionResultId',v_result.id,'acceptanceKind',v_acceptance.acceptance_kind,'domainResult',v_domain);
end;
$function$;

revoke all on function atlas.worker_record_production_pot_up_self_api_v1(uuid,uuid,jsonb,date,text,text) from public,anon;
grant execute on function atlas.worker_record_production_pot_up_self_api_v1(uuid,uuid,jsonb,date,text,text) to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,evidence,anonymous_execute_expected
) values(
  'atlas.worker_record_production_pot_up_self_api_v1(uuid, uuid, jsonb, date, text, text)',
  'app_endpoint','verified','active',true,true,true,1,1,
  jsonb_build_object(
    'source','atlas_worker_pot_up_structured_result_v1',
    'purpose','Return physical pot-up outputs from the current governed Worker Day.',
    'truthBoundary','Requires current employee identity, seat, credential, unit appointment, delegated Responsibility, active execution plan, exact Worker Day projection, exact materialized pot-up task, and per-physical-tray living counts. Domain evidence automatically advances Company Work; no manager approval is required.',
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
