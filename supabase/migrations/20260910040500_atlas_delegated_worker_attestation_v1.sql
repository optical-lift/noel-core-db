begin;

-- Delegated responsibility is operational authority for ordinary governed work.
-- A responsible employee's completed attestation may therefore become institutional
-- truth without a second manager click. Approval remains a separate contract class.

insert into atlas.work_result_contract_policies(
  contract_key, source_domain, acceptance_mode, active, description, metadata
) values (
  'ordinary_company_work_worker_attestation_v1',
  'organization',
  'worker_attestation',
  true,
  'Ordinary delegated Company Work where the current responsible employee attests completion and Atlas advances institutional work automatically.',
  jsonb_build_object(
    'workerDoneIsReport',true,
    'delegatedResponsibilityCarriesCompletionAuthority',true,
    'workerAttestationAcceptedByContract',true,
    'secondManagerClickRequired',false,
    'laterCorrectionReopensWithoutErasingHistory',true
  )
)
on conflict(contract_key) do update set
  source_domain=excluded.source_domain,
  acceptance_mode=excluded.acceptance_mode,
  active=excluded.active,
  description=excluded.description,
  metadata=excluded.metadata,
  updated_at=now();

create or replace function atlas.worker_report_company_work_projection_self_api_v1(
  p_projection_id uuid,
  p_result_kind text,
  p_idempotency_key text,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_uid uuid:=auth.uid();
  v_projection atlas.worker_week_projection%rowtype;
  v_farm_id uuid;
  v_context jsonb;
  v_work_ids uuid[];
  v_work atlas.work_items%rowtype;
  v_policy atlas.work_result_contract_policies%rowtype;
  v_allocation atlas.work_allocations%rowtype;
  v_plan atlas.work_execution_plans%rowtype;
  v_existing atlas.work_execution_results%rowtype;
  v_existing_acceptance atlas.work_result_acceptances%rowtype;
  v_result atlas.work_execution_results%rowtype;
  v_acceptance atlas.work_result_acceptances%rowtype;
  v_kind text:=lower(btrim(coalesce(p_result_kind,'')));
  v_key text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
  v_service_date date;
begin
  if v_uid is null then raise exception 'Authenticated employee required.' using errcode='42501'; end if;
  if p_projection_id is null then raise exception 'Worker Day projection required.' using errcode='22023'; end if;
  if v_kind not in ('completed','partial','blocked','unable') then raise exception 'Unsupported Company Work result kind.' using errcode='22023'; end if;
  if v_key is null or length(v_key)>160 then raise exception 'A valid result idempotency key is required.' using errcode='22023'; end if;
  if p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception 'Company Work result payload must be an object.' using errcode='22023'; end if;

  select * into v_projection from atlas.worker_week_projection p where p.id=p_projection_id;
  if v_projection.id is null then raise exception 'Worker Day projection was not found.' using errcode='P0002'; end if;

  select fm.farm_id into v_farm_id from atlas.farm_memberships fm where fm.id=v_projection.membership_id;
  if v_farm_id is null then raise exception 'Worker delivery membership was not found.' using errcode='P0002'; end if;

  v_context:=atlas.organization_employee_worker_context_self_v1(v_farm_id,v_projection.membership_id);
  if not coalesce((v_context->>'ok')::boolean,false) then
    raise exception 'Employee Worker Day authority required: %',coalesce(v_context->>'reason','unknown') using errcode='42501';
  end if;

  if v_projection.organization_id is distinct from (v_context->>'organizationId')::uuid
     or v_projection.organization_membership_id is distinct from (v_context->>'organizationMembershipId')::uuid then
    raise exception 'Worker Day projection does not belong to the current employee relationship.' using errcode='42501';
  end if;

  select array_agg(s.work_item_id order by s.work_item_id) into v_work_ids
  from atlas.worker_week_projection_sources s
  where s.projection_id=v_projection.id and s.source_role='required';

  if coalesce(array_length(v_work_ids,1),0)=0 then
    return jsonb_build_object('state','no_required_company_work','projectionId',v_projection.id);
  end if;
  if array_length(v_work_ids,1)<>1 then
    return jsonb_build_object('state','multiple_required_company_work','projectionId',v_projection.id,'workItemIds',to_jsonb(v_work_ids));
  end if;

  select * into v_work
  from atlas.work_items w
  where w.id=v_work_ids[1]
    and w.organization_id=(v_context->>'organizationId')::uuid;
  if v_work.id is null then raise exception 'Required Company Work was not found in the employee organization.' using errcode='P0002'; end if;
  if v_work.work_state<>'open' then
    return jsonb_build_object('state','company_work_not_open','projectionId',v_projection.id,'workItemId',v_work.id,'workState',v_work.work_state);
  end if;
  if v_work.organization_unit_id is distinct from (v_context->>'organizationUnitId')::uuid then
    raise exception 'Company Work is outside the employee position unit.' using errcode='42501';
  end if;

  select * into v_policy
  from atlas.work_result_contract_policies p
  where p.contract_key=v_work.result_contract_key and p.active;
  if v_policy.contract_key is null then
    return jsonb_build_object('state','ungoverned_result_contract','projectionId',v_projection.id,'workItemId',v_work.id);
  end if;
  if v_policy.acceptance_mode not in ('worker_attestation','manager_acceptance') then
    return jsonb_build_object('state','different_result_contract','projectionId',v_projection.id,'workItemId',v_work.id,'acceptanceMode',v_policy.acceptance_mode);
  end if;

  select * into v_allocation
  from atlas.work_allocations a
  where a.organization_id=v_work.organization_id
    and a.work_item_id=v_work.id
    and a.allocation_role='responsible'
    and a.state='active'
    and a.assignee_membership_id=(v_context->>'organizationMembershipId')::uuid
  limit 1;
  if v_allocation.id is null then
    raise exception 'Company Work result requires current delegated Responsibility for this employee.' using errcode='23514';
  end if;

  v_service_date:=(v_context->>'serviceDate')::date;
  select * into v_plan
  from atlas.work_execution_plans p
  where p.organization_id=v_work.organization_id
    and p.work_item_id=v_work.id
    and p.responsible_allocation_id=v_allocation.id
    and p.assignee_membership_id=(v_context->>'organizationMembershipId')::uuid
    and p.plan_state='active'
    and p.exposure_service_date=v_service_date
  limit 1;
  if v_plan.id is null then
    raise exception 'Company Work result may only come from the employee current governed Worker Day plan.' using errcode='23514';
  end if;

  select * into v_existing
  from atlas.work_execution_results r
  where r.organization_id=v_work.organization_id and r.idempotency_key=v_key;
  if v_existing.id is not null then
    if v_existing.work_item_id<>v_work.id
       or v_existing.result_kind<>v_kind
       or coalesce(v_existing.metadata->>'projectionId','')<>v_projection.id::text then
      raise exception 'Company Work result idempotency key collision.' using errcode='23505';
    end if;
    select * into v_existing_acceptance
    from atlas.work_result_acceptances a
    where a.execution_result_id=v_existing.id;
    select * into v_work from atlas.work_items w where w.id=v_work.id;
    return jsonb_build_object(
      'state','deduplicated','projectionId',v_projection.id,'workItemId',v_work.id,
      'resultId',v_existing.id,'resultKind',v_existing.result_kind,
      'acceptanceDecision',v_existing_acceptance.decision,'companyWorkState',v_work.work_state
    );
  end if;

  insert into atlas.work_execution_results(
    organization_id,work_item_id,responsible_allocation_id,task_id,
    reported_by_user_id,reported_by_farm_membership_id,reported_by_organization_membership_id,
    result_kind,result_contract_key,idempotency_key,payload,metadata
  ) values(
    v_work.organization_id,v_work.id,v_allocation.id,null,
    v_uid,v_projection.membership_id,(v_context->>'organizationMembershipId')::uuid,
    v_kind,v_policy.contract_key,v_key,p_payload,
    jsonb_build_object(
      'source','worker_report_company_work_projection_self_api_v1',
      'projectionId',v_projection.id,
      'managerPlanId',v_plan.id,
      'employeeSeatId',v_context->>'employeeSeatId',
      'delegatedResponsibility',true,
      'acceptanceMode',v_policy.acceptance_mode
    )
  ) returning * into v_result;

  if v_kind='completed' and v_policy.acceptance_mode='worker_attestation' then
    insert into atlas.work_result_acceptances(
      organization_id,work_item_id,execution_result_id,decision,acceptance_kind,
      accepted_by_domain,evidence,metadata
    ) values(
      v_work.organization_id,v_work.id,v_result.id,'accepted','delegated_worker_attestation',
      'organization',
      jsonb_strip_nulls(jsonb_build_object(
        'resultContractKey',v_policy.contract_key,
        'responsibleAllocationId',v_allocation.id,
        'reportedByOrganizationMembershipId',v_result.reported_by_organization_membership_id,
        'employeeSeatId',v_context->>'employeeSeatId',
        'positionId',v_context->>'positionId',
        'positionKey',v_context->>'positionKey'
      )),
      jsonb_build_object(
        'source','worker_report_company_work_projection_self_api_v1',
        'institutionalRule','delegated_responsibility_accepts_worker_attestation'
      )
    ) returning * into v_acceptance;

    update atlas.work_items
    set work_state='completed',completed_at=coalesce(completed_at,now()),updated_at=now()
    where id=v_work.id and work_state='open';

    update atlas.work_allocations
    set state='completed',completed_at=coalesce(completed_at,now()),updated_at=now()
    where id=v_allocation.id and state='active';
  end if;

  select * into v_work from atlas.work_items w where w.id=v_work.id;

  return jsonb_build_object(
    'state',case when v_acceptance.id is not null then 'reported_and_accepted' else 'reported' end,
    'projectionId',v_projection.id,'workItemId',v_work.id,
    'resultId',v_result.id,'resultKind',v_result.result_kind,
    'resultContractKey',v_result.result_contract_key,
    'acceptanceMode',v_policy.acceptance_mode,
    'acceptanceDecision',v_acceptance.decision,
    'acceptanceKind',v_acceptance.acceptance_kind,
    'companyWorkState',v_work.work_state
  );
end;
$function$;

create or replace function atlas.bridge_employee_worker_done_to_company_work_result_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_governed_count integer;
  v_result jsonb;
begin
  if new.event_kind<>'done_reported' or new.actor_user_id is null then return new; end if;
  if auth.uid() is null or auth.uid()<>new.actor_user_id then return new; end if;

  select count(*)::integer into v_governed_count
  from atlas.worker_week_projection_sources s
  join atlas.work_items w on w.id=s.work_item_id
  join atlas.work_result_contract_policies p on p.contract_key=w.result_contract_key and p.active
  where s.projection_id=new.projection_id
    and s.source_role='required'
    and p.acceptance_mode in ('worker_attestation','manager_acceptance');

  if v_governed_count<>1 then return new; end if;

  v_result:=atlas.worker_report_company_work_projection_self_api_v1(
    new.projection_id,
    'completed',
    left('worker-day-done:'||new.id::text,160),
    jsonb_build_object('workerDeliveryEventId',new.id,'reportedFrom','Worker Day')
  );

  if coalesce(v_result->>'state','') not in ('reported','reported_and_accepted','deduplicated') then
    raise exception 'Worker Day completion report could not enter Company Work result history: %',v_result using errcode='23514';
  end if;
  return new;
end;
$function$;

create or replace function atlas.bridge_employee_worker_reopen_to_company_work_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_work_id uuid;
  v_result atlas.work_execution_results%rowtype;
  v_plan atlas.work_execution_plans%rowtype;
begin
  if new.event_kind<>'completion_reopened' or new.actor_user_id is null then return new; end if;
  if auth.uid() is null or auth.uid()<>new.actor_user_id then return new; end if;

  select w.id into v_work_id
  from atlas.worker_week_projection_sources s
  join atlas.work_items w on w.id=s.work_item_id
  join atlas.work_result_contract_policies p on p.contract_key=w.result_contract_key and p.active
  where s.projection_id=new.projection_id
    and s.source_role='required'
    and p.acceptance_mode='worker_attestation'
  order by w.id
  limit 1;

  if v_work_id is null then return new; end if;

  select r.* into v_result
  from atlas.work_execution_results r
  join atlas.work_result_acceptances a on a.execution_result_id=r.id and a.decision='accepted'
  where r.work_item_id=v_work_id
    and r.organization_id=new.organization_id
    and r.reported_by_user_id=new.actor_user_id
    and r.reported_by_organization_membership_id=new.organization_membership_id
    and r.result_kind='completed'
    and coalesce(r.metadata->>'projectionId','')=new.projection_id::text
    and a.acceptance_kind='delegated_worker_attestation'
  order by r.reported_at desc,r.id desc
  limit 1;

  if v_result.id is null then return new; end if;

  update atlas.work_items
  set work_state='open',completed_at=null,updated_at=now(),
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
        'lastReopenedAt',clock_timestamp(),
        'lastReopenedByUserId',new.actor_user_id,
        'lastReopenEventId',new.id
      )
  where id=v_work_id and work_state='completed';

  update atlas.work_allocations
  set state='active',completed_at=null,updated_at=now()
  where id=v_result.responsible_allocation_id and state='completed';

  select * into v_plan
  from atlas.work_execution_plans p
  where p.work_item_id=v_work_id and p.responsible_allocation_id=v_result.responsible_allocation_id
  order by p.updated_at desc,p.id desc
  limit 1;

  if v_plan.id is not null and v_plan.plan_state='completed' then
    update atlas.work_execution_plans set plan_state='active',updated_at=now() where id=v_plan.id;
    insert into atlas.work_execution_plan_events(
      organization_id,work_item_id,plan_id,event_kind,
      from_planned_service_date,to_planned_service_date,
      from_exposure_service_date,to_exposure_service_date,
      actor_membership_id,reason,metadata
    ) values(
      v_plan.organization_id,v_plan.work_item_id,v_plan.id,'rescheduled',
      v_plan.planned_service_date,v_plan.planned_service_date,
      v_plan.exposure_service_date,v_plan.exposure_service_date,
      new.organization_membership_id,
      'Responsible worker reopened previously attested Company Work.',
      jsonb_build_object(
        'source','bridge_employee_worker_reopen_to_company_work_v1',
        'workerDeliveryEventId',new.id,
        'priorExecutionResultId',v_result.id,
        'historyPreserved',true
      )
    );
  end if;

  return new;
end;
$function$;

drop trigger if exists worker_delivery_employee_reopen_company_work_v1 on atlas.worker_delivery_pilot_events;
create trigger worker_delivery_employee_reopen_company_work_v1
after insert on atlas.worker_delivery_pilot_events
for each row
when (new.event_kind='completion_reopened' and new.actor_user_id is not null)
execute function atlas.bridge_employee_worker_reopen_to_company_work_v1();

-- The live Gate 3 vertical slice is ordinary delegated nursery work. Keep its
-- stable Company Work identity while changing only the completion contract.
update atlas.work_items
set result_contract_key='ordinary_company_work_worker_attestation_v1',
    metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'completionAuthority','delegated_worker_attestation',
      'secondManagerClickRequired',false
    ),
    updated_at=now()
where stable_key='elm_pot_shasta_2026_09_09'
  and organization_id=(select id from atlas.organizations where lower(name)=lower('Elm Farm') limit 1)
  and work_state='open';

update atlas.authenticated_rpc_registry
set evidence=jsonb_build_object(
      'source','atlas_delegated_worker_attestation_v1',
      'purpose','Record a signed-in employee report against the single required Company Work item carried by a governed Worker Day projection.',
      'truthBoundary','Current employee identity, seat, credential, unit appointment, delegated Responsibility, and active manager plan are all required. Worker-attestation contracts auto-accept completed reports; explicit-approval contracts remain separate.',
      'classificationRuleVersion',3
    ),
    reviewed_at=now()
where signature='atlas.worker_report_company_work_projection_self_api_v1(uuid, text, text, jsonb)';

commit;
