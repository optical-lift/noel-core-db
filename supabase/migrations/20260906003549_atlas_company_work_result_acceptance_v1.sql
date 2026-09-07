create table if not exists atlas.work_result_contract_policies(
  contract_key text primary key,
  source_domain text not null,
  acceptance_mode text not null check (acceptance_mode in ('worker_attestation','structured_submission','domain_adapter')),
  active boolean not null default true,
  description text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists atlas.work_execution_results(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  work_item_id uuid not null references atlas.work_items(id) on delete cascade,
  responsible_allocation_id uuid references atlas.work_allocations(id) on delete set null,
  task_id uuid references atlas.tasks(id) on delete set null,
  reported_by_user_id uuid references auth.users(id) on delete set null,
  reported_by_farm_membership_id uuid references atlas.farm_memberships(id) on delete set null,
  reported_by_organization_membership_id uuid references atlas.organization_memberships(id) on delete set null,
  result_kind text not null check (result_kind in ('completed','partial','blocked','unable')),
  result_contract_key text not null references atlas.work_result_contract_policies(contract_key),
  idempotency_key text not null,
  payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload)='object'),
  reported_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  constraint work_execution_results_work_org_fk foreign key(organization_id,work_item_id)
    references atlas.work_items(organization_id,id) on delete cascade,
  constraint work_execution_results_org_membership_fk foreign key(organization_id,reported_by_organization_membership_id)
    references atlas.organization_memberships(organization_id,id),
  unique(organization_id,idempotency_key)
);

create table if not exists atlas.work_result_acceptances(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  work_item_id uuid not null references atlas.work_items(id) on delete cascade,
  execution_result_id uuid not null references atlas.work_execution_results(id) on delete cascade,
  decision text not null check (decision in ('accepted','rejected')),
  acceptance_kind text not null,
  accepted_by_domain text not null,
  accepted_at timestamptz not null default now(),
  evidence jsonb not null default '{}'::jsonb check (jsonb_typeof(evidence)='object'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  constraint work_result_acceptances_work_org_fk foreign key(organization_id,work_item_id)
    references atlas.work_items(organization_id,id) on delete cascade,
  unique(execution_result_id)
);

create index if not exists work_execution_results_work_time_idx
  on atlas.work_execution_results(organization_id,work_item_id,reported_at desc,id desc);
create index if not exists work_result_acceptances_work_idx
  on atlas.work_result_acceptances(organization_id,work_item_id,accepted_at desc,id desc);

alter table atlas.work_result_contract_policies enable row level security;
alter table atlas.work_execution_results enable row level security;
alter table atlas.work_result_acceptances enable row level security;
revoke all on atlas.work_result_contract_policies from anon,authenticated;
revoke all on atlas.work_execution_results from anon,authenticated;
revoke all on atlas.work_result_acceptances from anon,authenticated;

insert into atlas.work_result_contract_policies(
  contract_key,source_domain,acceptance_mode,active,description,metadata
) values(
  'production_bed_preparation_v1',
  'production',
  'worker_attestation',
  true,
  'The responsible worker may attest that the assigned destination preparation is complete. Normal Done is sufficient; no additional result form is required.',
  jsonb_build_object(
    'normalDoneRequiresPrompt',false,
    'workerDoneIsReport',true,
    'workerAttestationAcceptedByContract',true,
    'blockedDoesNotComplete',true,
    'sourceDomainStillOwnsDownstreamProductionTruth',true
  )
)
on conflict(contract_key) do update set
  source_domain=excluded.source_domain,
  acceptance_mode=excluded.acceptance_mode,
  active=excluded.active,
  description=excluded.description,
  metadata=atlas.work_result_contract_policies.metadata||excluded.metadata,
  updated_at=now();

create or replace function atlas.block_company_work_result_history_mutation_v1()
returns trigger
language plpgsql
set search_path='pg_catalog','atlas'
as $$ begin
  raise exception 'Company Work result history is append-only.' using errcode='55000';
end $$;

drop trigger if exists work_execution_results_append_only_v1 on atlas.work_execution_results;
create trigger work_execution_results_append_only_v1
before update or delete on atlas.work_execution_results
for each row execute function atlas.block_company_work_result_history_mutation_v1();

drop trigger if exists work_result_acceptances_append_only_v1 on atlas.work_result_acceptances;
create trigger work_result_acceptances_append_only_v1
before update or delete on atlas.work_result_acceptances
for each row execute function atlas.block_company_work_result_history_mutation_v1();

create or replace function atlas.prepare_company_work_task_result_v1(
  p_task_id uuid,
  p_farm_membership_id uuid,
  p_result_kind text,
  p_idempotency_key text,
  p_payload jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer
set search_path='pg_catalog','atlas','auth'
as $$
declare
  v_task atlas.tasks%rowtype;
  v_farm_member atlas.farm_memberships%rowtype;
  v_work atlas.work_items%rowtype;
  v_adapter atlas.work_execution_adapters%rowtype;
  v_policy atlas.work_result_contract_policies%rowtype;
  v_allocation atlas.work_allocations%rowtype;
  v_org_member atlas.organization_memberships%rowtype;
  v_plan atlas.work_execution_plans%rowtype;
  v_result atlas.work_execution_results%rowtype;
  v_acceptance atlas.work_result_acceptances%rowtype;
  v_submission_id uuid;
  v_key text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
  v_kind text:=lower(btrim(coalesce(p_result_kind,'')));
  v_timezone text:='America/Chicago';
  v_today date;
begin
  if v_key is null or length(v_key)>160 then
    raise exception 'A valid result idempotency key is required.' using errcode='22023';
  end if;
  if v_kind not in ('completed','partial','blocked','unable') then
    raise exception 'Unsupported Company Work result kind.' using errcode='22023';
  end if;
  if p_payload is null or jsonb_typeof(p_payload)<>'object' then
    raise exception 'Company Work result payload must be an object.' using errcode='22023';
  end if;

  select * into v_task from atlas.tasks where id=p_task_id;
  if v_task.id is null then raise exception 'Task was not found.' using errcode='P0002'; end if;

  select a.* into v_adapter
  from atlas.work_execution_adapters a
  join atlas.work_items wi on wi.organization_id=a.organization_id and wi.id=a.work_item_id
  where a.task_id=v_task.id
    and wi.work_state='open'
  order by case when a.state='active' then 0 else 1 end,a.created_at desc
  limit 1;
  if v_adapter.id is null then
    return jsonb_build_object('state','no_open_company_work','taskId',v_task.id);
  end if;

  select * into v_work from atlas.work_items
  where id=v_adapter.work_item_id and organization_id=v_adapter.organization_id;
  if v_work.result_contract_key is null then
    return jsonb_build_object('state','ungoverned_result_contract','taskId',v_task.id,'workItemId',v_work.id);
  end if;
  select * into v_policy from atlas.work_result_contract_policies
  where contract_key=v_work.result_contract_key and active;
  if v_policy.contract_key is null then
    return jsonb_build_object('state','unregistered_result_contract','taskId',v_task.id,'workItemId',v_work.id,'resultContractKey',v_work.result_contract_key);
  end if;

  select * into v_farm_member from atlas.farm_memberships
  where id=p_farm_membership_id and farm_id=v_task.farm_id and active;
  if v_farm_member.id is null
     or v_farm_member.role<>'farm_hand'
     or v_task.assigned_membership_id is distinct from v_farm_member.id then
    raise exception 'Company Work result must come from the assigned active worker membership.' using errcode='42501';
  end if;
  if auth.uid() is not null and auth.uid()<>v_farm_member.user_id then
    raise exception 'Company Work result actor does not match the signed-in worker.' using errcode='42501';
  end if;

  select * into v_allocation from atlas.work_allocations
  where organization_id=v_work.organization_id and work_item_id=v_work.id
    and state='active' and allocation_role='responsible'
  limit 1;
  if v_allocation.id is null then
    raise exception 'Company Work completion/report requires active Responsibility.' using errcode='23514';
  end if;
  select * into v_org_member from atlas.organization_memberships
  where id=v_allocation.assignee_membership_id and organization_id=v_work.organization_id and active;
  if v_org_member.id is null or v_org_member.user_id<>v_farm_member.user_id then
    raise exception 'Worker result actor does not match canonical Company Work Responsibility.' using errcode='23514';
  end if;

  if coalesce(v_work.metadata->>'managerSchedulingAuthority','')='work_execution_plans' then
    select * into v_plan from atlas.work_execution_plans
    where organization_id=v_work.organization_id and work_item_id=v_work.id
      and plan_state='active' and responsible_allocation_id=v_allocation.id
      and assignee_membership_id=v_org_member.id
    limit 1;
    if v_plan.id is null then
      raise exception 'Company Work is not on an active manager plan for this worker.' using errcode='23514';
    end if;
    select coalesce(nullif(f.metadata->>'timezone',''),'America/Chicago') into v_timezone
    from atlas.farms f where f.id=v_task.farm_id;
    if not exists(select 1 from pg_timezone_names where name=v_timezone) then v_timezone:='America/Chicago'; end if;
    v_today:=(now() at time zone v_timezone)::date;
    if v_plan.exposure_service_date<>v_today then
      raise exception 'Company Work result may only be returned from the currently exposed Worker Day.' using errcode='23514';
    end if;
  end if;

  select * into v_result from atlas.work_execution_results
  where organization_id=v_work.organization_id and idempotency_key=v_key;
  if v_result.id is not null then
    if v_result.work_item_id<>v_work.id or v_result.task_id is distinct from v_task.id or v_result.result_kind<>v_kind then
      raise exception 'Company Work result idempotency key collision.' using errcode='23505';
    end if;
    select * into v_acceptance from atlas.work_result_acceptances where execution_result_id=v_result.id;
    return jsonb_build_object(
      'state','deduplicated','resultId',v_result.id,'workItemId',v_work.id,
      'resultKind',v_result.result_kind,'acceptanceDecision',v_acceptance.decision,'acceptanceKind',v_acceptance.acceptance_kind
    );
  end if;

  if v_kind='completed' and v_policy.acceptance_mode='domain_adapter' then
    raise exception 'This Work must be completed through its domain result flow, not ordinary Done.' using errcode='23514';
  end if;

  if v_kind='completed' and v_policy.acceptance_mode='structured_submission' then
    select s.id into v_submission_id
    from atlas.work_result_submissions s
    where s.organization_id=v_work.organization_id
      and s.task_id=v_task.id
      and s.effective_membership_id=v_farm_member.id
    order by s.submitted_at desc,s.id desc
    limit 1;
    if v_submission_id is null then
      raise exception 'This Work requires its structured result before Done can be accepted.' using errcode='23514';
    end if;
  end if;

  insert into atlas.work_execution_results(
    organization_id,work_item_id,responsible_allocation_id,task_id,
    reported_by_user_id,reported_by_farm_membership_id,reported_by_organization_membership_id,
    result_kind,result_contract_key,idempotency_key,payload,metadata
  ) values(
    v_work.organization_id,v_work.id,v_allocation.id,v_task.id,
    v_farm_member.user_id,v_farm_member.id,v_org_member.id,
    v_kind,v_policy.contract_key,v_key,p_payload,
    jsonb_strip_nulls(jsonb_build_object(
      'source','worker_task_transition',
      'executionAdapterId',v_adapter.id,
      'managerPlanId',v_plan.id,
      'structuredSubmissionId',v_submission_id
    ))
  ) returning * into v_result;

  if v_kind='completed' and v_policy.acceptance_mode in ('worker_attestation','structured_submission') then
    insert into atlas.work_result_acceptances(
      organization_id,work_item_id,execution_result_id,decision,acceptance_kind,accepted_by_domain,evidence,metadata
    ) values(
      v_work.organization_id,v_work.id,v_result.id,'accepted',
      case when v_policy.acceptance_mode='worker_attestation' then 'contract_worker_attestation' else 'structured_submission_validated' end,
      v_policy.source_domain,
      jsonb_strip_nulls(jsonb_build_object(
        'resultContractKey',v_policy.contract_key,
        'structuredSubmissionId',v_submission_id,
        'responsibleAllocationId',v_allocation.id,
        'reportedByOrganizationMembershipId',v_org_member.id
      )),
      jsonb_build_object('source','prepare_company_work_task_result_v1')
    ) returning * into v_acceptance;
  end if;

  return jsonb_build_object(
    'state','reported','resultId',v_result.id,'workItemId',v_work.id,'resultKind',v_result.result_kind,
    'acceptanceDecision',v_acceptance.decision,'acceptanceKind',v_acceptance.acceptance_kind,
    'resultContractKey',v_policy.contract_key,'acceptanceMode',v_policy.acceptance_mode
  );
end;
$$;

create or replace function atlas.guard_governed_company_work_completion_v1()
returns trigger
language plpgsql security definer
set search_path='pg_catalog','atlas'
as $$
begin
  if old.work_state is distinct from new.work_state and new.work_state='completed'
     and new.result_contract_key is not null
     and exists(
       select 1 from atlas.work_result_contract_policies p
       where p.contract_key=new.result_contract_key and p.active
     )
     and not exists(
       select 1
       from atlas.work_result_acceptances a
       join atlas.work_execution_results r on r.id=a.execution_result_id
       where a.organization_id=new.organization_id
         and a.work_item_id=new.id
         and a.decision='accepted'
         and r.organization_id=new.organization_id
         and r.work_item_id=new.id
         and r.result_kind='completed'
         and r.result_contract_key=new.result_contract_key
     ) then
    raise exception 'Company Work completion requires accepted result evidence for contract %.',new.result_contract_key using errcode='23514';
  end if;
  return new;
end;
$$;

drop trigger if exists a_work_items_guard_governed_completion_v1 on atlas.work_items;
create trigger a_work_items_guard_governed_completion_v1
before update of work_state on atlas.work_items
for each row execute function atlas.guard_governed_company_work_completion_v1();

create or replace function atlas.worker_record_task_transition_v1(
  p_task_id uuid,
  p_transition text,
  p_idempotency_key text,
  p_note text default null,
  p_reason text default null,
  p_payload jsonb default '{}'::jsonb,
  p_target_date date default null,
  p_lane_key text default null,
  p_work_key text default null,
  p_existing_field_log_id uuid default null
) returns jsonb
language plpgsql security definer
set search_path='pg_catalog','atlas'
as $$
declare
  v_farm_id uuid;
  v_visibility_scope text;
  v_assigned_membership_id uuid;
  v_task_type text;
  v_current_membership_id uuid;
  v_role text;
  v_payload jsonb;
  v_readiness jsonb;
  v_transition_card jsonb;
  v_timezone text := 'America/Chicago';
  v_service_date date;
  v_company_result jsonb;
begin
  select t.farm_id,t.visibility_scope,t.assigned_membership_id,t.task_type
  into v_farm_id,v_visibility_scope,v_assigned_membership_id,v_task_type
  from atlas.tasks t
  where t.id=p_task_id;

  if v_farm_id is null then raise exception 'Task not found.' using errcode='P0002'; end if;
  select coalesce(nullif(f.metadata->>'timezone',''),'America/Chicago') into v_timezone
  from atlas.farms f where f.id=v_farm_id;
  v_service_date := (now() at time zone coalesce(v_timezone,'America/Chicago'))::date;
  v_role := atlas.current_farm_role(v_farm_id);
  v_current_membership_id := atlas.current_membership_id(v_farm_id);

  if v_role not in ('farm_hand','manager')
    or v_current_membership_id is null
    or v_visibility_scope <> 'assigned_worker'
    or v_assigned_membership_id <> v_current_membership_id then
    raise exception 'This task is not assigned to the signed-in farm member.' using errcode='42501';
  end if;

  if p_transition not in ('done','partial','blocked','not_relevant','changed_plan','rescheduled','unfinished','checklist_done','checklist_open','note') then
    raise exception 'Unsupported assigned-worker transition.' using errcode='22023';
  end if;
  if v_role='farm_hand' and p_transition in ('rescheduled','changed_plan','not_relevant') then
    raise exception 'Farm hands cannot move, reschedule, or close assigned work as a plan change.' using errcode='42501';
  end if;
  if p_transition in ('rescheduled','unfinished') and p_target_date is null then
    raise exception 'A target date is required for this transition.' using errcode='22023';
  end if;

  if p_transition='done'
     and coalesce(p_payload->>'structuredResultKind','')='flower_preparation_directive_final_tally_v1' then
    return atlas.record_flower_preparation_directive_result_for_member_v2(
      p_task_id,coalesce(p_payload->'lines','[]'::jsonb),coalesce(p_payload->'workerAddedLines','[]'::jsonb),
      coalesce(p_payload->'remainingStems','[]'::jsonb),p_idempotency_key
    );
  end if;

  if p_transition='done' and v_task_type='flower_fulfillment' then
    return atlas.record_flower_fulfillment_core_v1(
      p_task_id,v_current_membership_id,v_role,p_note,p_idempotency_key,false
    );
  end if;

  if p_transition='done' then
    v_readiness := atlas.task_execution_readiness_v1(p_task_id);
    v_transition_card := atlas.worker_state_transition_card_v2(v_farm_id,v_current_membership_id,p_task_id,v_service_date);
    if not coalesce((v_readiness->>'ready')::boolean,false)
       or coalesce(v_transition_card#>>'{transition,state}','') <> 'authorized_for_routed_day' then
      raise exception 'This work is not executable in current farm reality.' using errcode='23514';
    end if;
  end if;

  if p_transition in ('done','partial','blocked') and v_role='farm_hand' then
    v_company_result:=atlas.prepare_company_work_task_result_v1(
      p_task_id,
      v_current_membership_id,
      case p_transition when 'done' then 'completed' when 'partial' then 'partial' else 'blocked' end,
      p_idempotency_key,
      jsonb_strip_nulls(jsonb_build_object(
        'transition',p_transition,
        'note',nullif(btrim(coalesce(p_note,'')),''),
        'reason',nullif(btrim(coalesce(p_reason,'')),''),
        'workerPayload',coalesce(p_payload,'{}'::jsonb),
        'serviceDate',v_service_date
      ))
    );
  end if;

  v_payload := coalesce(p_payload,'{}'::jsonb) || jsonb_build_object(
    'actor_user_id',auth.uid(),
    'actor_membership_id',v_current_membership_id,
    'actor_role',v_role
  );
  if v_company_result is not null then
    v_payload:=v_payload||jsonb_build_object('companyWorkResult',v_company_result);
  end if;

  return atlas.record_task_transition_v1(
    p_task_id,p_transition,p_idempotency_key,p_target_date,p_note,p_reason,p_lane_key,p_work_key,v_payload,p_existing_field_log_id
  );
end;
$$;

create or replace function atlas.worker_task_requires_structured_result_v1(p_task_id uuid)
returns boolean
language plpgsql stable security definer
set search_path='pg_catalog','atlas'
as $$
declare
  v_task atlas.tasks%rowtype;
  v_metadata jsonb;
  v_route text;
  v_created_from text;
  v_joined text;
  v_quick text;
  v_acceptance_mode text;
begin
  select * into v_task from atlas.tasks where id=p_task_id;
  if v_task.id is null then return true; end if;

  select p.acceptance_mode into v_acceptance_mode
  from atlas.work_execution_adapters a
  join atlas.work_items wi on wi.organization_id=a.organization_id and wi.id=a.work_item_id
  join atlas.work_result_contract_policies p on p.contract_key=wi.result_contract_key and p.active
  where a.task_id=v_task.id
  order by case when a.state='active' then 0 else 1 end,a.created_at desc
  limit 1;
  if v_acceptance_mode='worker_attestation' then return false; end if;
  if v_acceptance_mode in ('structured_submission','domain_adapter') then return true; end if;

  v_metadata:=coalesce(v_task.metadata,'{}'::jsonb);
  v_route:=lower(btrim(coalesce(v_metadata->>'work_route','')));
  v_created_from:=lower(btrim(coalesce(v_metadata->>'created_from','')));
  v_joined:=lower(concat_ws(' ',v_task.task_type,v_task.action_key,v_task.generated_from,v_route,v_created_from));
  v_quick:=lower(btrim(coalesce(v_metadata->>'quick_complete_allowed','')));

  if v_quick in ('true','yes','1') then return false; end if;
  if v_quick in ('false','no','0') then return true; end if;
  if lower(btrim(coalesce(v_metadata->>'structured_result_required',''))) in ('true','yes','1')
     or lower(btrim(coalesce(v_metadata->>'result_capture_required',''))) in ('true','yes','1')
     or lower(btrim(coalesce(v_metadata->>'planting_log_required',''))) in ('true','yes','1')
     or lower(btrim(coalesce(v_metadata->>'requires_result',''))) in ('true','yes','1')
     or nullif(btrim(coalesce(v_metadata->>'capture_kind','')),'') is not null then return true; end if;
  if lower(coalesce(v_task.action_key,''))='thin'
     and lower(coalesce(v_task.task_type,''))='thinning'
     and lower(coalesce(v_task.operation_class,''))='remove_uproot' then return false; end if;
  if v_route in ('crop_cycle','seed','plant','harvest')
     or v_created_from='crop_cycle_triggered_sequence'
     or v_metadata ? 'crop_cycle_id'
     or v_metadata ? 'crop_cycle_key'
     or v_metadata ? 'crop_profile_stable_key'
     or lower(coalesce(v_task.action_key,'')) in ('sow','seed_sowing','plant','transplant','harvest')
     or v_joined ~ '(germination|harvest|transplant|planting|readiness|production)' then return true; end if;
  return false;
end;
$$;

create or replace function atlas.organization_owner_company_work_planning_queue_api_v2(
  p_organization_id uuid,
  p_window_start date default null,
  p_window_end date default null
) returns table(
  work_item_id uuid,title text,operation_class text,work_state text,
  responsibility_state text,responsible_membership_id uuid,responsible_user_id uuid,allocation_id uuid,
  planning_state text,planned_service_date date,exposure_service_date date,first_planned_service_date date,rollover_count integer,
  next_target_at timestamptz,hard_finish_at timestamptz,result_contract_key text,open_conflicts bigint,
  latest_result_kind text,latest_result_at timestamptz,latest_result_payload jsonb,attention_state text
)
language plpgsql stable security definer
set search_path='pg_catalog','atlas','auth'
as $$
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if not atlas.is_organization_owner(p_organization_id) then raise exception 'Organization owner authority required.' using errcode='42501'; end if;
  return query
  select wi.id,wi.title,wi.operation_class,wi.work_state,
    case when wa.id is null then 'unassigned' else 'assigned' end,
    wa.assignee_membership_id,om.user_id,wa.id,
    case when wa.id is null then 'unassigned' when ep.id is null then 'assigned_unscheduled' when ep.plan_state='needs_replan' then 'needs_replan' else 'scheduled' end,
    ep.planned_service_date,ep.exposure_service_date,ep.first_planned_service_date,coalesce(ep.rollover_count,0),
    tc.preferred_end_at,coalesce(tc.hard_finish_at,tc.latest_lawful_at),wi.result_contract_key,coalesce(pc.open_conflicts,0),
    lr.result_kind,lr.reported_at,lr.payload,
    case
      when lr.result_kind in ('blocked','unable') then 'worker_exception'
      when ep.plan_state='needs_replan' then 'needs_replan'
      when wa.id is null then 'needs_responsibility'
      when ep.id is null then 'needs_schedule'
      else 'none'
    end
  from atlas.work_items wi
  left join atlas.work_allocations wa on wa.organization_id=wi.organization_id and wa.work_item_id=wi.id and wa.state='active' and wa.allocation_role='responsible'
  left join atlas.organization_memberships om on om.id=wa.assignee_membership_id
  left join atlas.work_execution_plans ep on ep.organization_id=wi.organization_id and ep.work_item_id=wi.id and ep.plan_state in ('active','needs_replan')
  left join lateral(
    select preferred_end_at,hard_finish_at,latest_lawful_at from atlas.work_time_contracts x
    where x.organization_id=wi.organization_id and x.work_item_id=wi.id and x.contract_state='active'
    order by x.created_at desc limit 1
  ) tc on true
  left join lateral(
    select count(*) open_conflicts from atlas.work_planning_conflicts c
    where c.organization_id=wi.organization_id and c.work_item_id=wi.id and c.state='open'
  ) pc on true
  left join lateral(
    select r.result_kind,r.reported_at,r.payload from atlas.work_execution_results r
    where r.organization_id=wi.organization_id and r.work_item_id=wi.id
    order by r.reported_at desc,r.id desc limit 1
  ) lr on true
  where wi.organization_id=p_organization_id and wi.work_state='open'
    and (p_window_start is null or coalesce(ep.exposure_service_date,(tc.preferred_end_at at time zone 'UTC')::date,(tc.hard_finish_at at time zone 'UTC')::date)>=p_window_start)
    and (p_window_end is null or coalesce(ep.exposure_service_date,(tc.preferred_end_at at time zone 'UTC')::date,(tc.hard_finish_at at time zone 'UTC')::date)<=p_window_end)
  order by case
      when lr.result_kind in ('blocked','unable') then 0
      when wa.id is null then 1
      when ep.id is null then 2
      when ep.plan_state='needs_replan' then 3
      else 4
    end,
    coalesce(ep.exposure_service_date,(tc.preferred_end_at at time zone 'UTC')::date,(tc.hard_finish_at at time zone 'UTC')::date) nulls last,
    wi.created_at,wi.id;
end;
$$;

revoke all on function atlas.organization_owner_company_work_planning_queue_api_v2(uuid,date,date) from public;
grant execute on function atlas.organization_owner_company_work_planning_queue_api_v2(uuid,date,date) to authenticated;