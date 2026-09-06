alter table atlas.organization_memberships
  add column if not exists eligibility_begins_on date,
  add column if not exists eligibility_ends_on date;

alter table atlas.farm_memberships
  add column if not exists eligibility_begins_on date,
  add column if not exists eligibility_ends_on date;

do $$ begin
  alter table atlas.organization_memberships
    add constraint organization_memberships_eligibility_window_check
    check (eligibility_begins_on is null or eligibility_ends_on is null or eligibility_ends_on >= eligibility_begins_on);
exception when duplicate_object then null; end $$;
do $$ begin
  alter table atlas.farm_memberships
    add constraint farm_memberships_eligibility_window_check
    check (eligibility_begins_on is null or eligibility_ends_on is null or eligibility_ends_on >= eligibility_begins_on);
exception when duplicate_object then null; end $$;

create or replace function atlas.organization_membership_eligible_on_date_v1(
  p_membership_id uuid,
  p_organization_id uuid,
  p_service_date date
) returns boolean
language sql stable security definer
set search_path='pg_catalog','atlas'
as $$
  select exists(
    select 1
    from atlas.organization_memberships m
    where m.id=p_membership_id
      and m.organization_id=p_organization_id
      and m.active
      and p_service_date is not null
      and (m.eligibility_begins_on is null or m.eligibility_begins_on<=p_service_date)
      and (m.eligibility_ends_on is null or m.eligibility_ends_on>=p_service_date)
  )
$$;

create or replace function atlas.farm_membership_eligible_on_date_v1(
  p_membership_id uuid,
  p_farm_id uuid,
  p_service_date date
) returns boolean
language sql stable security definer
set search_path='pg_catalog','atlas'
as $$
  select exists(
    select 1
    from atlas.farm_memberships m
    where m.id=p_membership_id
      and m.farm_id=p_farm_id
      and m.active
      and p_service_date is not null
      and (m.eligibility_begins_on is null or m.eligibility_begins_on<=p_service_date)
      and (m.eligibility_ends_on is null or m.eligibility_ends_on>=p_service_date)
  )
$$;

create table if not exists atlas.work_execution_plans(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  work_item_id uuid not null references atlas.work_items(id) on delete cascade,
  responsible_allocation_id uuid not null references atlas.work_allocations(id) on delete restrict,
  assignee_membership_id uuid not null references atlas.organization_memberships(id) on delete restrict,
  planned_by_membership_id uuid references atlas.organization_memberships(id) on delete set null,
  plan_state text not null default 'active' check (plan_state in ('active','needs_replan','withdrawn','completed')),
  first_planned_service_date date not null,
  planned_service_date date not null,
  exposure_service_date date not null,
  rollover_count integer not null default 0 check (rollover_count>=0),
  plan_reason text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint work_execution_plans_work_org_fk foreign key(organization_id,work_item_id)
    references atlas.work_items(organization_id,id) on delete cascade,
  constraint work_execution_plans_assignee_org_fk foreign key(organization_id,assignee_membership_id)
    references atlas.organization_memberships(organization_id,id),
  constraint work_execution_plans_planner_org_fk foreign key(organization_id,planned_by_membership_id)
    references atlas.organization_memberships(organization_id,id)
);

create unique index if not exists work_execution_plans_one_current_idx
  on atlas.work_execution_plans(work_item_id)
  where plan_state in ('active','needs_replan');
create index if not exists work_execution_plans_worker_day_idx
  on atlas.work_execution_plans(organization_id,assignee_membership_id,exposure_service_date,plan_state);

create table if not exists atlas.work_execution_plan_events(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  work_item_id uuid not null references atlas.work_items(id) on delete cascade,
  plan_id uuid not null references atlas.work_execution_plans(id) on delete cascade,
  event_kind text not null check (event_kind in ('planned','rescheduled','carried_forward','needs_replan','withdrawn','completed','carrier_projected')),
  from_planned_service_date date,
  to_planned_service_date date,
  from_exposure_service_date date,
  to_exposure_service_date date,
  actor_membership_id uuid references atlas.organization_memberships(id) on delete set null,
  reason text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now()
);
create index if not exists work_execution_plan_events_plan_idx
  on atlas.work_execution_plan_events(plan_id,created_at,id);

alter table atlas.work_execution_plans enable row level security;
alter table atlas.work_execution_plan_events enable row level security;
revoke all on atlas.work_execution_plans from anon,authenticated;
revoke all on atlas.work_execution_plan_events from anon,authenticated;

create or replace function atlas.validate_work_execution_plan_v1()
returns trigger
language plpgsql security definer
set search_path='pg_catalog','atlas'
as $$
declare
  v_work atlas.work_items%rowtype;
  v_allocation atlas.work_allocations%rowtype;
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
    if not atlas.organization_membership_eligible_on_date_v1(new.assignee_membership_id,new.organization_id,new.planned_service_date)
       or not atlas.organization_membership_eligible_on_date_v1(new.assignee_membership_id,new.organization_id,new.exposure_service_date) then
      raise exception 'The responsible person is not eligible for the planned/exposed service date.' using errcode='23514';
    end if;
  end if;
  new.updated_at:=now();
  return new;
end;
$$;

drop trigger if exists work_execution_plans_validate_v1 on atlas.work_execution_plans;
create trigger work_execution_plans_validate_v1
before insert or update on atlas.work_execution_plans
for each row execute function atlas.validate_work_execution_plan_v1();

create or replace function atlas.company_work_execution_plan_window_check_v1(
  p_work_item_id uuid,
  p_service_date date
) returns jsonb
language plpgsql stable security definer
set search_path='pg_catalog','atlas'
as $$
declare
  v_farm_id uuid;
  v_timezone text:='UTC';
  v_start timestamptz;
  v_end timestamptz;
  v_contract atlas.work_time_contracts%rowtype;
begin
  select pwo.farm_id into v_farm_id
  from atlas.work_execution_adapters a
  join atlas.planned_work_occurrences pwo on pwo.id=a.planned_occurrence_id
  where a.work_item_id=p_work_item_id and a.state='active'
  order by a.created_at limit 1;

  if v_farm_id is not null then
    select coalesce(nullif(metadata->>'timezone',''),'America/Chicago') into v_timezone
    from atlas.farms where id=v_farm_id;
  end if;
  if not exists(select 1 from pg_timezone_names where name=v_timezone) then v_timezone:='UTC'; end if;
  v_start:=p_service_date::timestamp at time zone v_timezone;
  v_end:=(p_service_date+1)::timestamp at time zone v_timezone;

  select * into v_contract
  from atlas.work_time_contracts
  where work_item_id=p_work_item_id and contract_state='active'
  order by created_at desc limit 1;

  if v_contract.id is null then
    return jsonb_build_object('state','no_source_time_contract','allowed',true,'timezone',v_timezone);
  end if;
  if v_contract.earliest_lawful_at is not null and v_end<=v_contract.earliest_lawful_at then
    return jsonb_build_object('state','before_lawful_window','allowed',false,'contractId',v_contract.id,'timezone',v_timezone);
  end if;
  if coalesce(v_contract.hard_finish_at,v_contract.latest_lawful_at) is not null
     and v_start>=coalesce(v_contract.hard_finish_at,v_contract.latest_lawful_at) then
    return jsonb_build_object('state','after_lawful_window','allowed',false,'contractId',v_contract.id,'timezone',v_timezone);
  end if;
  return jsonb_build_object('state','within_lawful_window','allowed',true,'contractId',v_contract.id,'timezone',v_timezone);
end;
$$;

create or replace function atlas.set_company_work_execution_plan_internal_v1(
  p_work_item_id uuid,
  p_service_date date,
  p_planned_by_membership_id uuid default null,
  p_reason text default null,
  p_provenance jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer
set search_path='pg_catalog','atlas'
as $$
declare
  v_work atlas.work_items%rowtype;
  v_allocation atlas.work_allocations%rowtype;
  v_plan atlas.work_execution_plans%rowtype;
  v_old atlas.work_execution_plans%rowtype;
  v_window jsonb;
  v_event_kind text;
begin
  if p_service_date is null then raise exception 'A planned service date is required.' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('atlas.company_work.plan:'||p_work_item_id::text,0));
  select * into v_work from atlas.work_items where id=p_work_item_id for update;
  if v_work.id is null then raise exception 'Company Work item was not found.' using errcode='P0002'; end if;
  if v_work.work_state<>'open' then raise exception 'Only open Company Work can be planned.' using errcode='22023'; end if;

  select * into v_allocation
  from atlas.work_allocations
  where work_item_id=v_work.id and organization_id=v_work.organization_id
    and state='active' and allocation_role='responsible'
  limit 1;
  if v_allocation.id is null then
    raise exception 'Responsibility must be established before a worker day can be planned.' using errcode='23514';
  end if;
  if not atlas.organization_membership_eligible_on_date_v1(v_allocation.assignee_membership_id,v_work.organization_id,p_service_date) then
    raise exception 'The responsible person is not eligible on the planned service date.' using errcode='23514';
  end if;

  v_window:=atlas.company_work_execution_plan_window_check_v1(v_work.id,p_service_date);
  if not coalesce((v_window->>'allowed')::boolean,false) then
    raise exception 'The planned day is outside the source-owned lawful Work window (%).',v_window->>'state' using errcode='23514';
  end if;

  select * into v_old from atlas.work_execution_plans
  where work_item_id=v_work.id and plan_state in ('active','needs_replan') limit 1 for update;

  if v_old.id is not null and v_old.assignee_membership_id<>v_allocation.assignee_membership_id then
    update atlas.work_execution_plans
    set plan_state='withdrawn',plan_reason='Responsibility changed before re-planning.',metadata=metadata||jsonb_build_object('withdrawReason','responsibility_changed')
    where id=v_old.id;
    insert into atlas.work_execution_plan_events(
      organization_id,work_item_id,plan_id,event_kind,from_planned_service_date,from_exposure_service_date,
      actor_membership_id,reason,metadata
    ) values(v_old.organization_id,v_old.work_item_id,v_old.id,'withdrawn',v_old.planned_service_date,v_old.exposure_service_date,
      p_planned_by_membership_id,'Responsibility changed before re-planning.',coalesce(p_provenance,'{}'::jsonb));
    v_old:=null;
  end if;

  if v_old.id is null then
    insert into atlas.work_execution_plans(
      organization_id,work_item_id,responsible_allocation_id,assignee_membership_id,planned_by_membership_id,
      plan_state,first_planned_service_date,planned_service_date,exposure_service_date,rollover_count,plan_reason,metadata
    ) values(
      v_work.organization_id,v_work.id,v_allocation.id,v_allocation.assignee_membership_id,p_planned_by_membership_id,
      'active',p_service_date,p_service_date,p_service_date,0,nullif(btrim(coalesce(p_reason,'')),''),coalesce(p_provenance,'{}'::jsonb)
    ) returning * into v_plan;
    v_event_kind:='planned';
  else
    update atlas.work_execution_plans
    set responsible_allocation_id=v_allocation.id,
        assignee_membership_id=v_allocation.assignee_membership_id,
        planned_by_membership_id=coalesce(p_planned_by_membership_id,planned_by_membership_id),
        plan_state='active',
        planned_service_date=p_service_date,
        exposure_service_date=p_service_date,
        rollover_count=case when planned_service_date is distinct from p_service_date then 0 else rollover_count end,
        plan_reason=nullif(btrim(coalesce(p_reason,'')),''),
        metadata=metadata||coalesce(p_provenance,'{}'::jsonb)
    where id=v_old.id returning * into v_plan;
    v_event_kind:=case when v_old.planned_service_date is distinct from p_service_date or v_old.plan_state<>'active' then 'rescheduled' else 'planned' end;
  end if;

  insert into atlas.work_execution_plan_events(
    organization_id,work_item_id,plan_id,event_kind,from_planned_service_date,to_planned_service_date,
    from_exposure_service_date,to_exposure_service_date,actor_membership_id,reason,metadata
  ) values(
    v_plan.organization_id,v_plan.work_item_id,v_plan.id,v_event_kind,
    v_old.planned_service_date,v_plan.planned_service_date,v_old.exposure_service_date,v_plan.exposure_service_date,
    p_planned_by_membership_id,nullif(btrim(coalesce(p_reason,'')),''),coalesce(p_provenance,'{}'::jsonb)
  );

  perform atlas.sync_company_work_execution_plan_carrier_v1(v_work.id);

  return jsonb_build_object(
    'state','planned','workItemId',v_work.id,'planId',v_plan.id,
    'responsibleAllocationId',v_allocation.id,'assigneeMembershipId',v_allocation.assignee_membership_id,
    'plannedServiceDate',v_plan.planned_service_date,'exposureServiceDate',v_plan.exposure_service_date,
    'sourceWindow',v_window
  );
end;
$$;

create or replace function atlas.organization_owner_plan_company_work_api_v1(
  p_work_item_id uuid,
  p_service_date date,
  p_reason text default null
) returns jsonb
language plpgsql security definer
set search_path='pg_catalog','atlas','auth'
as $$
declare
  v_work atlas.work_items%rowtype;
  v_actor uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_work from atlas.work_items where id=p_work_item_id;
  if v_work.id is null then raise exception 'Company Work item was not found.' using errcode='P0002'; end if;
  if not atlas.is_organization_owner(v_work.organization_id) then raise exception 'Organization owner authority required.' using errcode='42501'; end if;
  select id into v_actor from atlas.organization_memberships
  where organization_id=v_work.organization_id and user_id=auth.uid() and active and role='owner'
  order by created_at limit 1;
  return atlas.set_company_work_execution_plan_internal_v1(
    p_work_item_id,p_service_date,v_actor,p_reason,
    jsonb_build_object('source','organization_owner_plan_company_work_api_v1','actorUserId',auth.uid())
  );
end;
$$;

create or replace function atlas.organization_owner_plan_company_work_week_api_v1(
  p_organization_id uuid,
  p_week_start date,
  p_plans jsonb
) returns jsonb
language plpgsql security definer
set search_path='pg_catalog','atlas','auth'
as $$
declare
  v_actor uuid;
  v_entry jsonb;
  v_work_id uuid;
  v_day date;
  v_results jsonb:='[]'::jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if not atlas.is_organization_owner(p_organization_id) then raise exception 'Organization owner authority required.' using errcode='42501'; end if;
  if p_week_start is null or p_week_start<>date_trunc('week',p_week_start::timestamp)::date then
    raise exception 'Week start must be a Monday.' using errcode='22023';
  end if;
  if jsonb_typeof(coalesce(p_plans,'[]'::jsonb))<>'array' then raise exception 'Plans must be an array.' using errcode='22023'; end if;
  if jsonb_array_length(coalesce(p_plans,'[]'::jsonb))>100 then raise exception 'Too many weekly plan entries.' using errcode='22023'; end if;
  select id into v_actor from atlas.organization_memberships
  where organization_id=p_organization_id and user_id=auth.uid() and active and role='owner'
  order by created_at limit 1;

  for v_entry in select value from jsonb_array_elements(coalesce(p_plans,'[]'::jsonb)) loop
    begin v_work_id:=(v_entry->>'workItemId')::uuid; exception when others then raise exception 'Each plan needs a valid workItemId.' using errcode='22023'; end;
    begin v_day:=(v_entry->>'serviceDate')::date; exception when others then raise exception 'Each plan needs a valid serviceDate.' using errcode='22023'; end;
    if v_day<p_week_start or v_day>p_week_start+6 then raise exception 'Every planned day must fall inside the supplied week.' using errcode='22023'; end if;
    if not exists(select 1 from atlas.work_items where id=v_work_id and organization_id=p_organization_id) then
      raise exception 'A weekly plan entry belongs to another organization.' using errcode='42501';
    end if;
    v_results:=v_results||jsonb_build_array(atlas.set_company_work_execution_plan_internal_v1(
      v_work_id,v_day,v_actor,v_entry->>'reason',jsonb_build_object('source','organization_owner_plan_company_work_week_api_v1','weekStart',p_week_start,'actorUserId',auth.uid())
    ));
  end loop;
  return jsonb_build_object('contractVersion','organization_owner_plan_company_work_week_api_v1','organizationId',p_organization_id,'weekStart',p_week_start,'plans',v_results);
end;
$$;

create or replace function atlas.organization_owner_clear_company_work_plan_api_v1(
  p_work_item_id uuid,
  p_reason text default null
) returns jsonb
language plpgsql security definer
set search_path='pg_catalog','atlas','auth'
as $$
declare
  v_work atlas.work_items%rowtype;
  v_plan atlas.work_execution_plans%rowtype;
  v_actor uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_work from atlas.work_items where id=p_work_item_id;
  if v_work.id is null then raise exception 'Company Work item was not found.' using errcode='P0002'; end if;
  if not atlas.is_organization_owner(v_work.organization_id) then raise exception 'Organization owner authority required.' using errcode='42501'; end if;
  select id into v_actor from atlas.organization_memberships
  where organization_id=v_work.organization_id and user_id=auth.uid() and active and role='owner'
  order by created_at limit 1;
  select * into v_plan from atlas.work_execution_plans where work_item_id=v_work.id and plan_state in ('active','needs_replan') limit 1 for update;
  if v_plan.id is null then return jsonb_build_object('state','already_unplanned','workItemId',v_work.id); end if;
  update atlas.work_execution_plans set plan_state='withdrawn',plan_reason=coalesce(nullif(btrim(p_reason),''),'manager_unplanned') where id=v_plan.id;
  insert into atlas.work_execution_plan_events(organization_id,work_item_id,plan_id,event_kind,from_planned_service_date,from_exposure_service_date,actor_membership_id,reason,metadata)
  values(v_plan.organization_id,v_plan.work_item_id,v_plan.id,'withdrawn',v_plan.planned_service_date,v_plan.exposure_service_date,v_actor,p_reason,jsonb_build_object('source','organization_owner_clear_company_work_plan_api_v1'));
  perform atlas.sync_company_work_execution_plan_carrier_v1(v_work.id);
  return jsonb_build_object('state','unplanned','workItemId',v_work.id,'planId',v_plan.id);
end;
$$;

create or replace function atlas.organization_owner_company_work_planning_queue_api_v1(
  p_organization_id uuid,
  p_window_start date default null,
  p_window_end date default null
) returns table(
  work_item_id uuid,
  title text,
  operation_class text,
  work_state text,
  responsibility_state text,
  responsible_membership_id uuid,
  responsible_user_id uuid,
  allocation_id uuid,
  planning_state text,
  planned_service_date date,
  exposure_service_date date,
  first_planned_service_date date,
  rollover_count integer,
  next_target_at timestamptz,
  hard_finish_at timestamptz,
  result_contract_key text,
  open_conflicts bigint
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
    case
      when wa.id is null then 'unassigned'
      when ep.id is null then 'assigned_unscheduled'
      when ep.plan_state='needs_replan' then 'needs_replan'
      else 'scheduled'
    end,
    ep.planned_service_date,ep.exposure_service_date,ep.first_planned_service_date,coalesce(ep.rollover_count,0),
    tc.preferred_end_at,coalesce(tc.hard_finish_at,tc.latest_lawful_at),wi.result_contract_key,
    coalesce(pc.open_conflicts,0)
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
  where wi.organization_id=p_organization_id and wi.work_state='open'
    and (p_window_start is null or coalesce(ep.exposure_service_date,(tc.preferred_end_at at time zone 'UTC')::date,(tc.hard_finish_at at time zone 'UTC')::date)>=p_window_start)
    and (p_window_end is null or coalesce(ep.exposure_service_date,(tc.preferred_end_at at time zone 'UTC')::date,(tc.hard_finish_at at time zone 'UTC')::date)<=p_window_end)
  order by case when wa.id is null then 0 when ep.id is null then 1 when ep.plan_state='needs_replan' then 2 else 3 end,
           coalesce(ep.exposure_service_date,(tc.preferred_end_at at time zone 'UTC')::date,(tc.hard_finish_at at time zone 'UTC')::date) nulls last,
           wi.created_at,wi.id;
end;
$$;

revoke all on function atlas.organization_owner_plan_company_work_api_v1(uuid,date,text) from public;
grant execute on function atlas.organization_owner_plan_company_work_api_v1(uuid,date,text) to authenticated;
revoke all on function atlas.organization_owner_plan_company_work_week_api_v1(uuid,date,jsonb) from public;
grant execute on function atlas.organization_owner_plan_company_work_week_api_v1(uuid,date,jsonb) to authenticated;
revoke all on function atlas.organization_owner_clear_company_work_plan_api_v1(uuid,text) from public;
grant execute on function atlas.organization_owner_clear_company_work_plan_api_v1(uuid,text) to authenticated;
revoke all on function atlas.organization_owner_company_work_planning_queue_api_v1(uuid,date,date) from public;
grant execute on function atlas.organization_owner_company_work_planning_queue_api_v1(uuid,date,date) to authenticated;