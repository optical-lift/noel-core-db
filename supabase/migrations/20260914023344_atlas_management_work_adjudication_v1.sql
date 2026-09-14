begin;

create table if not exists atlas.work_management_adjudications (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  work_item_id uuid not null references atlas.work_items(id) on delete cascade,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  actor_organization_membership_id uuid not null references atlas.organization_memberships(id) on delete restrict,
  actor_farm_membership_id uuid references atlas.farm_memberships(id) on delete set null,
  action text not null check (action in ('completed','not_relevant','new_data')),
  effective_at timestamptz not null default now(),
  reason text,
  payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload)='object'),
  idempotency_key text not null,
  created_at timestamptz not null default now(),
  unique (organization_id,idempotency_key),
  foreign key (organization_id,work_item_id)
    references atlas.work_items(organization_id,id) on delete cascade,
  foreign key (organization_id,actor_organization_membership_id)
    references atlas.organization_memberships(organization_id,id) on delete restrict
);

alter table atlas.work_management_adjudications enable row level security;
revoke all on table atlas.work_management_adjudications from public, anon, authenticated;
grant select on table atlas.work_management_adjudications to service_role;

create index if not exists work_management_adjudications_work_time_idx
  on atlas.work_management_adjudications(work_item_id,effective_at desc,created_at desc);

insert into atlas.work_result_contract_policies(
  contract_key,source_domain,acceptance_mode,active,description,metadata
) values (
  'management_adjudication_v1',
  'organization',
  'manager_acceptance',
  true,
  'Authorized management may adjudicate delegated Company Work directly. The management decision is preserved separately from worker testimony and domain evidence.',
  jsonb_build_object(
    'managementMayComplete',true,
    'managementMayMarkNotRelevant',true,
    'managementMaySupplyNewData',true,
    'workerIdentityNotRequiredForManagementDecision',true
  )
)
on conflict (contract_key) do update set
  source_domain=excluded.source_domain,
  acceptance_mode=excluded.acceptance_mode,
  active=true,
  description=excluded.description,
  metadata=atlas.work_result_contract_policies.metadata||excluded.metadata,
  updated_at=now();

create or replace function atlas.can_adjudicate_company_work_v1(p_work_item_id uuid)
returns boolean
language sql
stable
security definer
set search_path='pg_catalog','atlas','auth'
as $$
  select exists(
    select 1
    from atlas.work_items wi
    where wi.id=p_work_item_id
      and (
        atlas.is_organization_owner(wi.organization_id)
        or exists(
          select 1
          from atlas.organization_memberships om
          join atlas.farm_memberships fm
            on fm.user_id=om.user_id
           and fm.active
           and fm.role in ('owner','manager')
          join atlas.farms f
            on f.id=fm.farm_id
           and f.organization_id=wi.organization_id
          where om.organization_id=wi.organization_id
            and om.user_id=auth.uid()
            and om.active
            and (
              (wi.organization_unit_id is not null and f.organization_unit_id=wi.organization_unit_id)
              or exists(
                select 1
                from atlas.work_execution_adapters a
                join atlas.tasks t on t.id=a.task_id
                where a.work_item_id=wi.id
                  and a.organization_id=wi.organization_id
                  and t.farm_id=f.id
              )
              or exists(
                select 1
                from atlas.work_execution_adapters a
                join atlas.planned_work_occurrences pwo on pwo.id=a.planned_occurrence_id
                where a.work_item_id=wi.id
                  and a.organization_id=wi.organization_id
                  and pwo.farm_id=f.id
              )
              or exists(
                select 1
                from atlas.worker_week_projection_sources s
                join atlas.worker_week_projection p on p.id=s.projection_id
                where s.work_item_id=wi.id
                  and p.farm_id=f.id
              )
            )
        )
      )
  )
$$;

revoke all on function atlas.can_adjudicate_company_work_v1(uuid) from public, anon, authenticated;
grant execute on function atlas.can_adjudicate_company_work_v1(uuid) to service_role;

create or replace function atlas.organization_management_adjudicate_company_work_api_v1(
  p_work_item_id uuid,
  p_action text,
  p_payload jsonb default '{}'::jsonb,
  p_reason text default null,
  p_effective_at timestamptz default null,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','atlas','auth'
as $$
declare
  v_uid uuid:=auth.uid();
  v_action text:=lower(btrim(coalesce(p_action,'')));
  v_work atlas.work_items%rowtype;
  v_actor_org_membership_id uuid;
  v_actor_farm_membership_id uuid;
  v_allocation_id uuid;
  v_task_id uuid;
  v_contract_key text;
  v_effective timestamptz:=coalesce(p_effective_at,clock_timestamp());
  v_key text;
  v_adjudication atlas.work_management_adjudications%rowtype;
  v_result atlas.work_execution_results%rowtype;
begin
  if v_uid is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_work_item_id is null then raise exception 'Company Work item required.' using errcode='22023'; end if;
  if v_action not in ('completed','not_relevant','new_data') then
    raise exception 'Management action must be completed, not_relevant, or new_data.' using errcode='22023';
  end if;
  if jsonb_typeof(coalesce(p_payload,'{}'::jsonb))<>'object' then
    raise exception 'Management payload must be an object.' using errcode='22023';
  end if;

  select * into v_work from atlas.work_items where id=p_work_item_id for update;
  if v_work.id is null then raise exception 'Company Work item was not found.' using errcode='P0002'; end if;
  if not atlas.can_adjudicate_company_work_v1(v_work.id) then
    raise exception 'Management authority over this Company Work item is required.' using errcode='42501';
  end if;

  select om.id into v_actor_org_membership_id
  from atlas.organization_memberships om
  where om.organization_id=v_work.organization_id and om.user_id=v_uid and om.active
  order by case when om.role='owner' then 0 else 1 end,om.created_at,om.id
  limit 1;
  if v_actor_org_membership_id is null then
    raise exception 'Active organization membership required.' using errcode='42501';
  end if;

  select fm.id into v_actor_farm_membership_id
  from atlas.farm_memberships fm
  join atlas.farms f on f.id=fm.farm_id
  where fm.user_id=v_uid and fm.active and fm.role in ('owner','manager')
    and f.organization_id=v_work.organization_id
    and (
      v_work.organization_unit_id is null
      or f.organization_unit_id=v_work.organization_unit_id
      or exists(
        select 1 from atlas.work_execution_adapters a
        join atlas.tasks t on t.id=a.task_id
        where a.work_item_id=v_work.id and t.farm_id=f.id
      )
      or exists(
        select 1 from atlas.worker_week_projection_sources s
        join atlas.worker_week_projection p on p.id=s.projection_id
        where s.work_item_id=v_work.id and p.farm_id=f.id
      )
    )
  order by case fm.role when 'owner' then 0 else 1 end,fm.created_at,fm.id
  limit 1;

  v_key:=coalesce(nullif(btrim(coalesce(p_idempotency_key,'')),''),
    'management-adjudication:'||v_work.id::text||':'||v_action||':'||md5(v_effective::text||coalesce(p_reason,'')||coalesce(p_payload,'{}'::jsonb)::text));
  if length(v_key)>200 then raise exception 'Management idempotency key is too long.' using errcode='22023'; end if;

  insert into atlas.work_management_adjudications(
    organization_id,work_item_id,actor_user_id,actor_organization_membership_id,
    actor_farm_membership_id,action,effective_at,reason,payload,idempotency_key
  ) values (
    v_work.organization_id,v_work.id,v_uid,v_actor_org_membership_id,
    v_actor_farm_membership_id,v_action,v_effective,nullif(btrim(coalesce(p_reason,'')),''),
    coalesce(p_payload,'{}'::jsonb),v_key
  )
  on conflict (organization_id,idempotency_key) do update set idempotency_key=excluded.idempotency_key
  returning * into v_adjudication;

  if v_action='new_data' then
    return jsonb_build_object(
      'ok',true,'state','new_data_recorded','workItemId',v_work.id,
      'adjudicationId',v_adjudication.id,'companyWorkState',v_work.work_state
    );
  end if;

  if v_action='not_relevant' then
    if v_work.work_state='open' then
      update atlas.work_items
      set work_state='cancelled',cancelled_at=v_effective,completed_at=null,
          metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
            'lastManagementAdjudicationId',v_adjudication.id,
            'lastManagementAdjudication','not_relevant'
          ),updated_at=now()
      where id=v_work.id;

      update atlas.work_allocations
      set state='released',released_at=coalesce(released_at,v_effective),
          release_reason=coalesce(nullif(btrim(coalesce(p_reason,'')),''),'Management marked the work not relevant.'),
          updated_at=now()
      where work_item_id=v_work.id and state='active';

      update atlas.work_execution_adapters
      set state='retired',retired_at=coalesce(retired_at,v_effective),updated_at=now(),
          metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('managementAdjudicationId',v_adjudication.id)
      where work_item_id=v_work.id and state='active';

      update atlas.work_execution_plans
      set plan_state='withdrawn',updated_at=now(),
          metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('managementAdjudicationId',v_adjudication.id)
      where work_item_id=v_work.id and plan_state in ('active','needs_replan');
    end if;

    select * into v_work from atlas.work_items where id=v_work.id;
    return jsonb_build_object(
      'ok',true,'state','not_relevant','workItemId',v_work.id,
      'adjudicationId',v_adjudication.id,'companyWorkState',v_work.work_state
    );
  end if;

  if v_work.work_state='completed' then
    return jsonb_build_object(
      'ok',true,'state','already_completed','workItemId',v_work.id,
      'adjudicationId',v_adjudication.id,'companyWorkState',v_work.work_state
    );
  end if;
  if v_work.work_state<>'open' then
    raise exception 'Only open Company Work can be completed by management; current state is %.',v_work.work_state using errcode='23514';
  end if;

  select a.id into v_allocation_id
  from atlas.work_allocations a
  where a.work_item_id=v_work.id and a.state='active' and a.allocation_role='responsible'
  order by a.allocated_at desc,a.id desc limit 1;

  select a.task_id into v_task_id
  from atlas.work_execution_adapters a
  where a.work_item_id=v_work.id and a.state='active' and a.task_id is not null
  order by a.created_at desc,a.id desc limit 1;

  v_contract_key:=coalesce(v_work.result_contract_key,'management_adjudication_v1');

  insert into atlas.work_execution_results(
    organization_id,work_item_id,responsible_allocation_id,task_id,
    reported_by_user_id,reported_by_farm_membership_id,reported_by_organization_membership_id,
    result_kind,result_contract_key,idempotency_key,payload,reported_at,metadata
  ) values (
    v_work.organization_id,v_work.id,v_allocation_id,v_task_id,
    v_uid,v_actor_farm_membership_id,v_actor_org_membership_id,
    'completed',v_contract_key,left('management-adjudication-result:'||v_adjudication.id::text,200),
    jsonb_build_object(
      'managementAdjudicationId',v_adjudication.id,
      'managementDecision','completed',
      'suppliedData',coalesce(p_payload,'{}'::jsonb),
      'reason',nullif(btrim(coalesce(p_reason,'')),'')
    ),v_effective,
    jsonb_build_object(
      'source','organization_management_adjudicate_company_work_api_v1',
      'managementOverride',true,
      'workerReportRequired',false
    )
  )
  on conflict (organization_id,idempotency_key) do update set idempotency_key=excluded.idempotency_key
  returning * into v_result;

  insert into atlas.work_result_acceptances(
    organization_id,work_item_id,execution_result_id,decision,acceptance_kind,
    accepted_by_domain,evidence,metadata
  ) values (
    v_work.organization_id,v_work.id,v_result.id,'accepted','management_authority','organization',
    jsonb_build_object(
      'managementAdjudicationId',v_adjudication.id,
      'actorOrganizationMembershipId',v_actor_org_membership_id,
      'actorFarmMembershipId',v_actor_farm_membership_id,
      'originalResultContractKey',v_work.result_contract_key
    ),
    jsonb_build_object(
      'source','organization_management_adjudicate_company_work_api_v1',
      'managementDecisionIsInstitutionalAuthority',true,
      'domainEvidenceMayRemainSeparate',true
    )
  ) on conflict (execution_result_id) do nothing;

  update atlas.work_items
  set work_state='completed',completed_at=coalesce(completed_at,v_effective),cancelled_at=null,
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
        'lastManagementAdjudicationId',v_adjudication.id,
        'lastManagementAdjudication','completed'
      ),updated_at=now()
  where id=v_work.id and work_state='open';

  update atlas.work_allocations
  set state='completed',completed_at=coalesce(completed_at,v_effective),updated_at=now()
  where work_item_id=v_work.id and state='active';

  update atlas.work_execution_adapters
  set state='completed',completed_at=coalesce(completed_at,v_effective),updated_at=now(),
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('managementAdjudicationId',v_adjudication.id)
  where work_item_id=v_work.id and state='active';

  select * into v_work from atlas.work_items where id=v_work.id;
  return jsonb_build_object(
    'ok',true,'state','completed','workItemId',v_work.id,
    'adjudicationId',v_adjudication.id,'executionResultId',v_result.id,
    'companyWorkState',v_work.work_state
  );
end;
$$;

revoke all on function atlas.organization_management_adjudicate_company_work_api_v1(uuid,text,jsonb,text,timestamptz,text) from public, anon;
grant execute on function atlas.organization_management_adjudicate_company_work_api_v1(uuid,text,jsonb,text,timestamptz,text) to authenticated, service_role;

create or replace function atlas.organization_management_record_production_pot_up_api_v1(
  p_task_id uuid,
  p_outputs jsonb,
  p_care_date date default null,
  p_note text default null,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','atlas','auth'
as $$
declare
  v_uid uuid:=auth.uid();
  v_work_id uuid;
  v_result jsonb;
begin
  if v_uid is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_task_id is null then raise exception 'Pot-up task required.' using errcode='22023'; end if;

  select a.work_item_id into v_work_id
  from atlas.work_execution_adapters a
  where a.task_id=p_task_id and a.state='active'
  order by a.created_at desc,a.id desc limit 1;
  if v_work_id is null then raise exception 'Active Company Work adapter for the pot-up task was not found.' using errcode='P0002'; end if;
  if not atlas.can_adjudicate_company_work_v1(v_work_id) then
    raise exception 'Management authority over this pot-up work is required.' using errcode='42501';
  end if;

  v_result:=atlas.record_production_pot_up_v1(
    p_task_id,p_outputs,coalesce(p_care_date,current_date),p_note,p_idempotency_key
  );
  return jsonb_build_object(
    'ok',true,'state','production_pot_up_recorded_by_management',
    'workItemId',v_work_id,'domainResult',v_result
  );
end;
$$;

revoke all on function atlas.organization_management_record_production_pot_up_api_v1(uuid,jsonb,date,text,text) from public, anon;
grant execute on function atlas.organization_management_record_production_pot_up_api_v1(uuid,jsonb,date,text,text) to authenticated, service_role;

create or replace function atlas.accept_company_work_pot_up_domain_result_v1()
returns trigger
language plpgsql
security definer
set search_path='pg_catalog','atlas','auth'
as $$
declare
  v_adapter atlas.work_execution_adapters%rowtype;
  v_work atlas.work_items%rowtype;
  v_allocation atlas.work_allocations%rowtype;
  v_responsible_org_member atlas.organization_memberships%rowtype;
  v_assigned_farm_member atlas.farm_memberships%rowtype;
  v_actor_org_member atlas.organization_memberships%rowtype;
  v_actor_farm_member atlas.farm_memberships%rowtype;
  v_actor_authority text;
  v_expected_count integer;
  v_event_count integer;
  v_physical_count integer;
  v_physical_invalid integer;
  v_result atlas.work_execution_results%rowtype;
  v_key text;
  v_payload jsonb;
begin
  if old.status is not distinct from new.status or new.status<>'done' then return new; end if;
  select * into v_adapter from atlas.work_execution_adapters a where a.task_id=new.id and a.state='active' order by a.created_at desc limit 1;
  if v_adapter.id is null then return new; end if;
  select * into v_work from atlas.work_items w where w.id=v_adapter.work_item_id and w.organization_id=v_adapter.organization_id and w.work_state='open' and w.result_contract_key='production_pot_up_v1';
  if v_work.id is null then return new; end if;
  if lower(coalesce(new.action_key,''))<>'pot_up' and lower(coalesce(new.task_type,''))<>'pot_up' then raise exception 'Production pot-up Company Work can only close from a pot-up execution carrier.' using errcode='23514'; end if;
  select * into v_allocation from atlas.work_allocations a where a.organization_id=v_work.organization_id and a.work_item_id=v_work.id and a.state='active' and a.allocation_role='responsible' limit 1;
  if v_allocation.id is null then raise exception 'Production pot-up completion requires active delegated Responsibility.' using errcode='23514'; end if;
  select * into v_responsible_org_member from atlas.organization_memberships om where om.id=v_allocation.assignee_membership_id and om.organization_id=v_work.organization_id and om.active;
  select * into v_assigned_farm_member from atlas.farm_memberships fm where fm.id=new.assigned_membership_id and fm.farm_id=new.farm_id and fm.active;
  if v_responsible_org_member.id is null or v_assigned_farm_member.id is null or v_responsible_org_member.user_id is distinct from v_assigned_farm_member.user_id then
    raise exception 'Production pot-up delegated Responsibility is not aligned to the assigned worker.' using errcode='42501';
  end if;
  if auth.uid() is null then raise exception 'Signed-in worker or management authority required.' using errcode='42501'; end if;

  if auth.uid()=v_responsible_org_member.user_id then
    v_actor_org_member:=v_responsible_org_member;
    v_actor_farm_member:=v_assigned_farm_member;
    v_actor_authority:='responsible_worker';
  else
    select * into v_actor_org_member
    from atlas.organization_memberships om
    where om.organization_id=v_work.organization_id and om.user_id=auth.uid() and om.active
    order by case when om.role='owner' then 0 else 1 end,om.created_at,om.id limit 1;
    select * into v_actor_farm_member
    from atlas.farm_memberships fm
    where fm.farm_id=new.farm_id and fm.user_id=auth.uid() and fm.active and fm.role in ('owner','manager')
    order by case fm.role when 'owner' then 0 else 1 end,fm.created_at,fm.id limit 1;
    if v_actor_org_member.id is null or v_actor_farm_member.id is null or not atlas.can_adjudicate_company_work_v1(v_work.id) then
      raise exception 'Production pot-up result actor must be the responsible worker or authorized management.' using errcode='42501';
    end if;
    v_actor_authority:='management';
  end if;

  select count(distinct tc.crop_cycle_id)::integer into v_expected_count from atlas.task_crop_cycles tc join atlas.production_lot_crop_cycles plc on plc.crop_cycle_id=tc.crop_cycle_id and plc.relation_role='primary' join atlas.production_lots pl on pl.id=plc.production_lot_id and pl.lifecycle_status='active' where tc.task_id=new.id and tc.role in ('preserves','affects');
  select count(distinct e.crop_cycle_id)::integer into v_event_count from atlas.production_lot_events e join atlas.production_tray_batches b on b.id=e.tray_batch_id where e.task_id=new.id and e.event_type='pot_up_completed' and e.crop_cycle_id is not null and b.source_task_id=new.id and b.current_quantity is not null and b.current_quantity>0;
  if jsonb_typeof(new.metadata->'pot_up_physical_outputs')<>'array' then raise exception 'Pot-up completion requires physical tray output evidence.' using errcode='23514'; end if;
  select count(*)::integer into v_physical_count from jsonb_array_elements(new.metadata->'pot_up_physical_outputs') x where nullif(x->>'cropCycleId','') is not null;
  select count(*)::integer into v_physical_invalid from atlas.production_tray_batches b where b.source_task_id=new.id and not exists(select 1 from jsonb_array_elements(new.metadata->'pot_up_physical_outputs') g where g->>'cropCycleId'=b.crop_cycle_id::text and jsonb_typeof(g->'physicalTrays')='array' and jsonb_array_length(g->'physicalTrays')=b.tray_count::integer and (select count(distinct (t->>'trayNumber')::integer) from jsonb_array_elements(g->'physicalTrays') t)=jsonb_array_length(g->'physicalTrays') and (select sum((t->>'livingPlants')::numeric) from jsonb_array_elements(g->'physicalTrays') t)=b.current_quantity);
  if coalesce(v_expected_count,0)=0 or v_event_count<>v_expected_count or v_physical_count<>v_expected_count or v_physical_invalid<>0 then raise exception 'Pot-up completion evidence is incomplete or inconsistent (% crop cycles expected, % domain events, % physical output groups, % invalid batches).',v_expected_count,v_event_count,v_physical_count,v_physical_invalid using errcode='23514'; end if;
  v_key:='production-pot-up-domain:'||new.id::text;
  v_payload:=jsonb_build_object('taskId',new.id,'plannedOccurrenceId',new.planned_occurrence_id,'physicalOutputs',new.metadata->'pot_up_physical_outputs','productionEvents',(select coalesce(jsonb_agg(jsonb_build_object('eventId',e.id,'cropCycleId',e.crop_cycle_id,'productionLotId',e.production_lot_id,'trayBatchId',e.tray_batch_id,'eventDate',e.event_date,'livingPlants',e.quantity,'unit',e.unit) order by e.crop_cycle_id),'[]'::jsonb) from atlas.production_lot_events e where e.task_id=new.id and e.event_type='pot_up_completed'),'trayBatches',(select coalesce(jsonb_agg(jsonb_build_object('trayBatchId',b.id,'cropCycleId',b.crop_cycle_id,'containerKind',b.container_kind,'trayCount',b.tray_count,'livingPlants',b.current_quantity) order by b.crop_cycle_id),'[]'::jsonb) from atlas.production_tray_batches b where b.source_task_id=new.id));
  insert into atlas.work_execution_results(organization_id,work_item_id,responsible_allocation_id,task_id,reported_by_user_id,reported_by_farm_membership_id,reported_by_organization_membership_id,result_kind,result_contract_key,idempotency_key,payload,metadata) values(v_work.organization_id,v_work.id,v_allocation.id,new.id,auth.uid(),v_actor_farm_member.id,v_actor_org_member.id,'completed','production_pot_up_v1',v_key,v_payload,jsonb_build_object('source','accept_company_work_pot_up_domain_result_v1','domainEvidence','production_lot_events+production_tray_batches+physical_tray_attestation','delegatedResponsibility',true,'actorAuthority',v_actor_authority)) on conflict(organization_id,idempotency_key) do nothing;
  select * into v_result from atlas.work_execution_results r where r.organization_id=v_work.organization_id and r.idempotency_key=v_key;
  if v_result.work_item_id is distinct from v_work.id or v_result.task_id is distinct from new.id then raise exception 'Production pot-up result idempotency collision.' using errcode='23505'; end if;
  insert into atlas.work_result_acceptances(organization_id,work_item_id,execution_result_id,decision,acceptance_kind,accepted_by_domain,evidence,metadata) values(v_work.organization_id,v_work.id,v_result.id,'accepted','production_domain_adapter','production',jsonb_build_object('resultContractKey','production_pot_up_v1','responsibleAllocationId',v_allocation.id,'reportedByOrganizationMembershipId',v_actor_org_member.id,'productionEvidenceComplete',true,'physicalTrayEvidenceComplete',true,'actorAuthority',v_actor_authority),jsonb_build_object('source','accept_company_work_pot_up_domain_result_v1','managerApprovalRequired',false,'managementSubmissionAllowed',true)) on conflict(execution_result_id) do nothing;
  update atlas.work_items set work_state='completed',completed_at=coalesce(completed_at,new.completed_at,now()),updated_at=now() where id=v_work.id and work_state='open';
  update atlas.work_allocations set state='completed',completed_at=coalesce(completed_at,new.completed_at,now()),updated_at=now() where id=v_allocation.id and state='active';
  update atlas.work_execution_adapters set state='completed',completed_at=coalesce(completed_at,new.completed_at,now()),updated_at=now() where id=v_adapter.id and state='active';
  return new;
end;
$$;

revoke all on function atlas.accept_company_work_pot_up_domain_result_v1() from public, anon, authenticated;

delete from atlas.authenticated_rpc_registry
where signature in (
  'atlas.organization_management_adjudicate_company_work_api_v1(uuid, text, jsonb, text, timestamp with time zone, text)',
  'atlas.organization_management_record_production_pot_up_api_v1(uuid, jsonb, date, text, text)'
);

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,authenticated_execute_expected,
  security_definer_expected,service_execute_expected,caller_count,policy_reference_count,evidence,anonymous_execute_expected
) values
(
  'atlas.organization_management_adjudicate_company_work_api_v1(uuid, text, jsonb, text, timestamp with time zone, text)',
  'app_endpoint','verified','active',true,true,true,1,1,
  jsonb_build_object(
    'source','atlas_management_work_adjudication_v1',
    'purpose','Allow authorized organizational management to record completion, not-relevant, or new-data judgments over delegated Company Work.',
    'truthBoundary','Management authority changes Company Work state without impersonating the worker. Worker testimony and domain evidence remain separate append-only evidence.'
  ),false
),
(
  'atlas.organization_management_record_production_pot_up_api_v1(uuid, jsonb, date, text, text)',
  'app_endpoint','verified','active',true,true,true,1,1,
  jsonb_build_object(
    'source','atlas_management_work_adjudication_v1',
    'purpose','Allow authorized management to return real structured pot-up output when management has the physical facts.',
    'truthBoundary','Management may submit the same physical production facts as the responsible worker; actor identity and authority are preserved separately from delegated Responsibility.'
  ),false
);

commit;