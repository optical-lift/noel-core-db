BEGIN;

-- Reusable operational route patterns are execution configuration, not a new work,
-- responsibility, relationship, or policy authority. Concrete execution remains in
-- atlas.operational_routes; Company Work owns responsibility and scheduling;
-- external_relationships owns party relationship truth; Company Operating Knowledge
-- owns durable organization-specific procedure and policy.

create table if not exists atlas.operational_route_patterns (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  organization_unit_id uuid null references atlas.organization_units(id) on delete restrict,
  stable_key text not null,
  version integer not null default 1 check (version > 0),
  route_label text not null,
  route_kind text not null,
  status text not null default 'active',
  supersedes_id uuid null references atlas.operational_route_patterns(id) on delete restrict,
  operating_context jsonb not null default '{}'::jsonb,
  source_authority text not null default 'atlas',
  source_system_key text null,
  source_record_key text null,
  source_observed_at timestamptz null,
  metadata jsonb not null default '{}'::jsonb,
  created_by_user_id uuid null default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint operational_route_patterns_version_uq unique (organization_id, stable_key, version),
  constraint operational_route_patterns_kind_check check (route_kind = any (array['delivery'::text,'pickup'::text,'service'::text,'mixed'::text,'handoff'::text])),
  constraint operational_route_patterns_status_check check (status = any (array['draft'::text,'active'::text,'superseded'::text,'retired'::text])),
  constraint operational_route_patterns_source_authority_check check (source_authority = any (array['atlas'::text,'external'::text])),
  constraint operational_route_patterns_external_source_check check (source_authority <> 'external'::text or (nullif(btrim(source_system_key),'') is not null and nullif(btrim(source_record_key),'') is not null)),
  constraint operational_route_patterns_context_object_check check (jsonb_typeof(operating_context)='object'),
  constraint operational_route_patterns_metadata_object_check check (jsonb_typeof(metadata)='object')
);

create unique index if not exists operational_route_patterns_one_active_version_idx
  on atlas.operational_route_patterns (organization_id, stable_key)
  where status='active';

create index if not exists operational_route_patterns_unit_status_idx
  on atlas.operational_route_patterns (organization_id, organization_unit_id, status, route_label);

create table if not exists atlas.operational_route_pattern_stops (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  operational_route_pattern_id uuid not null references atlas.operational_route_patterns(id) on delete cascade,
  stable_key text not null,
  sequence_number integer not null,
  stop_kind text not null,
  external_relationship_id uuid null references atlas.external_relationships(id) on delete set null,
  destination_label text not null,
  address_text text null,
  operating_context jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint operational_route_pattern_stops_key_uq unique (operational_route_pattern_id, stable_key),
  constraint operational_route_pattern_stops_sequence_uq unique (operational_route_pattern_id, sequence_number),
  constraint operational_route_pattern_stops_sequence_positive check (sequence_number > 0),
  constraint operational_route_pattern_stops_kind_check check (stop_kind = any (array['product_delivery'::text,'product_pickup'::text,'service_visit'::text,'handoff'::text,'mixed'::text])),
  constraint operational_route_pattern_stops_context_object_check check (jsonb_typeof(operating_context)='object'),
  constraint operational_route_pattern_stops_metadata_object_check check (jsonb_typeof(metadata)='object')
);

create index if not exists operational_route_pattern_stops_relationship_idx
  on atlas.operational_route_pattern_stops (external_relationship_id)
  where external_relationship_id is not null;

alter table atlas.operational_routes
  add column if not exists organization_unit_id uuid null references atlas.organization_units(id) on delete restrict,
  add column if not exists operational_route_pattern_id uuid null references atlas.operational_route_patterns(id) on delete restrict,
  add column if not exists work_item_id uuid null references atlas.work_items(id) on delete restrict,
  add column if not exists work_execution_plan_id uuid null references atlas.work_execution_plans(id) on delete restrict;

alter table atlas.operational_route_stops
  add column if not exists external_relationship_id uuid null references atlas.external_relationships(id) on delete set null;

create index if not exists operational_routes_company_work_idx
  on atlas.operational_routes (organization_id, work_item_id, route_date)
  where work_item_id is not null;

create index if not exists operational_routes_pattern_idx
  on atlas.operational_routes (operational_route_pattern_id, route_date)
  where operational_route_pattern_id is not null;

create index if not exists operational_route_stops_external_relationship_idx
  on atlas.operational_route_stops (external_relationship_id)
  where external_relationship_id is not null;

comment on table atlas.operational_route_patterns is
  'Versioned reusable logistics shape for operational routes. A pattern is not work, assignment, policy, relationship truth, or execution truth; it becomes a dated route only through a materialization boundary.';
comment on column atlas.operational_route_patterns.operating_context is
  'Non-authoritative context keys available to downstream Company Operating Knowledge resolution. Durable procedure and policy belong in company_operating_knowledge, not here.';
comment on table atlas.operational_route_pattern_stops is
  'Ordered reusable stop topology. external_relationship_id points to the universal relationship spine; address_text is a routing locator snapshot, not canonical party identity or commercial truth.';
comment on column atlas.operational_route_pattern_stops.external_relationship_id is
  'Universal party/relationship link. Domain-specific buyer, vendor, donor, or service models may map to this relationship without making the route library domain-specific.';
comment on column atlas.operational_routes.work_item_id is
  'Company Work authority whose planned execution this route realizes. Null is retained for legacy or externally sourced route runs.';
comment on column atlas.operational_routes.work_execution_plan_id is
  'Exact manager-plan provenance used when a Company Work-backed route was materialized. Route date and assignee are snapshots of that plan at materialization time.';
comment on column atlas.operational_routes.operational_route_pattern_id is
  'Specific immutable-by-reference pattern version from which this concrete route was materialized.';
comment on column atlas.operational_route_stops.external_relationship_id is
  'Universal external relationship represented by this concrete stop, when known. Current relationship intelligence remains owned by external_relationships and its projections.';

create or replace function atlas.guard_operational_route_pattern_scope_v1()
returns trigger
language plpgsql
set search_path='pg_catalog','atlas'
as $$
declare
  v_pattern atlas.operational_route_patterns%rowtype;
  v_relationship atlas.external_relationships%rowtype;
  v_prior atlas.operational_route_patterns%rowtype;
begin
  if tg_table_name='operational_route_patterns' then
    if new.organization_unit_id is not null and not exists(
      select 1 from atlas.organization_units u
      where u.id=new.organization_unit_id and u.organization_id=new.organization_id
    ) then
      raise exception 'Route pattern organization unit belongs to another organization.' using errcode='23514';
    end if;

    if new.supersedes_id is not null then
      select * into v_prior from atlas.operational_route_patterns where id=new.supersedes_id;
      if v_prior.id is null
         or v_prior.organization_id<>new.organization_id
         or v_prior.stable_key<>new.stable_key
         or new.version<=v_prior.version then
        raise exception 'A route pattern may supersede only an earlier version of the same organization pattern.' using errcode='23514';
      end if;
    end if;
    return new;
  end if;

  select * into v_pattern
  from atlas.operational_route_patterns
  where id=new.operational_route_pattern_id;

  if v_pattern.id is null or v_pattern.organization_id<>new.organization_id then
    raise exception 'Route pattern stop must belong to the same organization as its pattern.' using errcode='23514';
  end if;

  if new.external_relationship_id is not null then
    select * into v_relationship
    from atlas.external_relationships
    where id=new.external_relationship_id;
    if v_relationship.id is null or v_relationship.organization_id<>new.organization_id then
      raise exception 'Route pattern stop relationship belongs to another organization.' using errcode='23514';
    end if;
    if v_pattern.organization_unit_id is not null
       and v_relationship.organization_unit_id is not null
       and v_pattern.organization_unit_id<>v_relationship.organization_unit_id then
      raise exception 'Route pattern stop relationship is scoped to a different organization unit.' using errcode='23514';
    end if;
  end if;
  return new;
end;
$$;

create trigger operational_route_patterns_scope_guard_v1
before insert or update on atlas.operational_route_patterns
for each row execute function atlas.guard_operational_route_pattern_scope_v1();

create trigger operational_route_pattern_stops_scope_guard_v1
before insert or update on atlas.operational_route_pattern_stops
for each row execute function atlas.guard_operational_route_pattern_scope_v1();

create or replace function atlas.guard_operational_route_company_work_scope_v1()
returns trigger
language plpgsql
set search_path='pg_catalog','atlas'
as $$
declare
  v_route atlas.operational_routes%rowtype;
  v_pattern atlas.operational_route_patterns%rowtype;
  v_work atlas.work_items%rowtype;
  v_plan atlas.work_execution_plans%rowtype;
  v_relationship atlas.external_relationships%rowtype;
begin
  if tg_table_name='operational_routes' then
    if new.organization_unit_id is not null and not exists(
      select 1 from atlas.organization_units u
      where u.id=new.organization_unit_id and u.organization_id=new.organization_id
    ) then
      raise exception 'Operational route organization unit belongs to another organization.' using errcode='23514';
    end if;

    if new.operational_route_pattern_id is not null then
      select * into v_pattern from atlas.operational_route_patterns where id=new.operational_route_pattern_id;
      if v_pattern.id is null or v_pattern.organization_id<>new.organization_id then
        raise exception 'Operational route pattern belongs to another organization.' using errcode='23514';
      end if;
      if new.organization_unit_id is not null and v_pattern.organization_unit_id is not null
         and new.organization_unit_id<>v_pattern.organization_unit_id then
        raise exception 'Operational route and route pattern disagree on organization unit.' using errcode='23514';
      end if;
    end if;

    if new.work_item_id is not null then
      select * into v_work from atlas.work_items where id=new.work_item_id;
      if v_work.id is null or v_work.organization_id<>new.organization_id then
        raise exception 'Operational route Company Work belongs to another organization.' using errcode='23514';
      end if;
      if new.organization_unit_id is not null and v_work.organization_unit_id is not null
         and new.organization_unit_id<>v_work.organization_unit_id then
        raise exception 'Operational route and Company Work disagree on organization unit.' using errcode='23514';
      end if;
    end if;

    if new.work_execution_plan_id is not null then
      if new.work_item_id is null then
        raise exception 'A route execution-plan link requires Company Work.' using errcode='23514';
      end if;
      select * into v_plan from atlas.work_execution_plans where id=new.work_execution_plan_id;
      if v_plan.id is null or v_plan.organization_id<>new.organization_id or v_plan.work_item_id<>new.work_item_id then
        raise exception 'Operational route execution plan does not belong to its Company Work.' using errcode='23514';
      end if;
    end if;
    return new;
  end if;

  select * into v_route from atlas.operational_routes where id=new.operational_route_id;
  if v_route.id is null or v_route.organization_id<>new.organization_id then
    raise exception 'Operational route stop must belong to the same organization as its route.' using errcode='23514';
  end if;

  if new.external_relationship_id is not null then
    select * into v_relationship from atlas.external_relationships where id=new.external_relationship_id;
    if v_relationship.id is null or v_relationship.organization_id<>new.organization_id then
      raise exception 'Operational route stop relationship belongs to another organization.' using errcode='23514';
    end if;
    if v_route.organization_unit_id is not null
       and v_relationship.organization_unit_id is not null
       and v_route.organization_unit_id<>v_relationship.organization_unit_id then
      raise exception 'Operational route stop relationship is scoped to a different organization unit.' using errcode='23514';
    end if;
  end if;
  return new;
end;
$$;

create trigger operational_routes_company_work_scope_guard_v1
before insert or update of organization_id,organization_unit_id,operational_route_pattern_id,work_item_id,work_execution_plan_id
on atlas.operational_routes
for each row execute function atlas.guard_operational_route_company_work_scope_v1();

create trigger operational_route_stops_relationship_scope_guard_v1
before insert or update of organization_id,operational_route_id,external_relationship_id
on atlas.operational_route_stops
for each row execute function atlas.guard_operational_route_company_work_scope_v1();

create or replace function atlas.materialize_operational_route_pattern_for_company_work_self_v1(
  p_operational_route_pattern_id uuid,
  p_work_item_id uuid,
  p_idempotency_key text,
  p_metadata jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','atlas','auth'
as $$
declare
  v_pattern atlas.operational_route_patterns%rowtype;
  v_work atlas.work_items%rowtype;
  v_plan atlas.work_execution_plans%rowtype;
  v_existing atlas.operational_routes%rowtype;
  v_route atlas.operational_routes%rowtype;
  v_stop atlas.operational_route_pattern_stops%rowtype;
  v_actor uuid;
  v_route_unit uuid;
  v_route_key text;
  v_stop_count integer:=0;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;
  if nullif(btrim(p_idempotency_key),'') is null then
    raise exception 'An idempotency key is required.' using errcode='22023';
  end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Route materialization metadata must be a JSON object.' using errcode='22023';
  end if;

  select * into v_pattern
  from atlas.operational_route_patterns
  where id=p_operational_route_pattern_id;
  if v_pattern.id is null or v_pattern.status<>'active' then
    raise exception 'An active operational route pattern is required.' using errcode='22023';
  end if;

  select * into v_work from atlas.work_items where id=p_work_item_id;
  if v_work.id is null or v_work.organization_id<>v_pattern.organization_id then
    raise exception 'Company Work and route pattern must belong to the same organization.' using errcode='23514';
  end if;
  if v_work.work_state<>'open' then
    raise exception 'Only open Company Work can materialize a route.' using errcode='22023';
  end if;
  if not atlas.can_schedule_company_work_v1(v_work.id) then
    raise exception 'Company Work scheduling authority required.' using errcode='42501';
  end if;
  v_actor:=atlas.company_work_planning_actor_membership_v1(v_work.id);
  if v_actor is null then
    raise exception 'An active organization membership with scheduling authority is required.' using errcode='42501';
  end if;

  select * into v_plan
  from atlas.work_execution_plans p
  where p.organization_id=v_work.organization_id
    and p.work_item_id=v_work.id
    and p.plan_state='active'
  order by p.updated_at desc,p.id desc
  limit 1;
  if v_plan.id is null then
    raise exception 'Company Work must have an active manager plan before a route can be materialized.' using errcode='22023';
  end if;

  if v_pattern.organization_unit_id is not null and v_work.organization_unit_id is not null
     and v_pattern.organization_unit_id<>v_work.organization_unit_id then
    raise exception 'Route pattern and Company Work belong to different organization units.' using errcode='23514';
  end if;
  v_route_unit:=coalesce(v_work.organization_unit_id,v_pattern.organization_unit_id);

  if not exists(
    select 1 from atlas.work_allocations a
    where a.id=v_plan.responsible_allocation_id
      and a.organization_id=v_work.organization_id
      and a.work_item_id=v_work.id
      and a.assignee_membership_id=v_plan.assignee_membership_id
      and a.allocation_role='responsible'
      and a.state='active'
  ) then
    raise exception 'The manager plan no longer has active Company Work responsibility.' using errcode='23514';
  end if;

  select * into v_existing
  from atlas.operational_routes r
  where r.organization_id=v_work.organization_id
    and r.idempotency_key=p_idempotency_key;
  if v_existing.id is not null then
    if v_existing.operational_route_pattern_id is distinct from v_pattern.id
       or v_existing.work_item_id is distinct from v_work.id
       or v_existing.work_execution_plan_id is distinct from v_plan.id then
      raise exception 'Conflicting route materialization replay.' using errcode='22023';
    end if;
    return jsonb_build_object(
      'contractVersion','operational_route_pattern_company_work_v1',
      'routeId',v_existing.id,
      'workItemId',v_work.id,
      'workExecutionPlanId',v_plan.id,
      'idempotentReplay',true
    );
  end if;

  if not exists(
    select 1 from atlas.operational_route_pattern_stops s
    where s.operational_route_pattern_id=v_pattern.id
  ) then
    raise exception 'An operational route pattern requires at least one stop before materialization.' using errcode='22023';
  end if;

  v_route_key:='pattern:'||v_pattern.id::text||':plan:'||v_plan.id::text;

  insert into atlas.operational_routes(
    organization_id,organization_unit_id,stable_key,route_date,route_label,route_kind,state,
    assigned_organization_membership_id,external_custodian_label,
    source_authority,idempotency_key,metadata,created_by_user_id,
    operational_route_pattern_id,work_item_id,work_execution_plan_id
  ) values (
    v_work.organization_id,v_route_unit,v_route_key,v_plan.exposure_service_date,
    v_pattern.route_label,v_pattern.route_kind,'planned',v_plan.assignee_membership_id,null,
    'atlas',p_idempotency_key,
    jsonb_build_object(
      'materialization','company_work_route_pattern_v1',
      'patternStableKey',v_pattern.stable_key,
      'patternVersion',v_pattern.version,
      'patternOperatingContext',v_pattern.operating_context,
      'companyWorkPlanSnapshot',jsonb_build_object(
        'plannedServiceDate',v_plan.planned_service_date,
        'exposureServiceDate',v_plan.exposure_service_date,
        'assigneeMembershipId',v_plan.assignee_membership_id,
        'responsibleAllocationId',v_plan.responsible_allocation_id
      )
    ) || p_metadata,
    auth.uid(),v_pattern.id,v_work.id,v_plan.id
  ) returning * into v_route;

  for v_stop in
    select * from atlas.operational_route_pattern_stops
    where operational_route_pattern_id=v_pattern.id
    order by sequence_number,id
  loop
    insert into atlas.operational_route_stops(
      organization_id,operational_route_id,stable_key,sequence_number,stop_kind,state,
      destination_label,address_text,assigned_organization_membership_id,
      source_authority,worker_instruction,metadata,external_relationship_id
    ) values (
      v_route.organization_id,v_route.id,v_stop.stable_key,v_stop.sequence_number,v_stop.stop_kind,'planned',
      v_stop.destination_label,v_stop.address_text,v_plan.assignee_membership_id,
      'atlas',null,
      jsonb_build_object(
        'routePatternStopId',v_stop.id,
        'routePatternOperatingContext',v_stop.operating_context,
        'routingLocatorSnapshot',case when v_stop.address_text is null then null else jsonb_build_object('addressText',v_stop.address_text) end
      ) || v_stop.metadata,
      v_stop.external_relationship_id
    );
    v_stop_count:=v_stop_count+1;
  end loop;

  return jsonb_build_object(
    'contractVersion','operational_route_pattern_company_work_v1',
    'routeId',v_route.id,
    'routeDate',v_route.route_date,
    'routePatternId',v_pattern.id,
    'workItemId',v_work.id,
    'workExecutionPlanId',v_plan.id,
    'assigneeMembershipId',v_plan.assignee_membership_id,
    'stopCount',v_stop_count,
    'idempotentReplay',false
  );
end;
$$;

comment on function atlas.materialize_operational_route_pattern_for_company_work_self_v1(uuid,uuid,text,jsonb) is
  'Materializes reusable route topology only after Company Work has real responsibility and an active manager plan. Assignment and execution date are inherited from Company Work planning; the route layer cannot invent them.';

create or replace view atlas.v_operational_route_execution_position_v1
with (security_invoker=true)
as
select
  r.id as operational_route_id,
  r.organization_id,
  r.organization_unit_id,
  r.stable_key,
  r.route_date,
  r.route_label,
  r.route_kind,
  r.state,
  r.assigned_organization_membership_id,
  r.operational_route_pattern_id,
  p.stable_key as route_pattern_stable_key,
  p.version as route_pattern_version,
  r.work_item_id,
  wi.title as company_work_title,
  wi.work_state as company_work_state,
  r.work_execution_plan_id,
  ep.plan_state as company_work_plan_state,
  case
    when r.work_item_id is not null then 'company_work_backed'
    when r.source_authority='external' then 'external'
    else 'legacy_direct'
  end as execution_authority_class,
  r.metadata,
  r.created_at,
  r.updated_at
from atlas.operational_routes r
left join atlas.operational_route_patterns p on p.id=r.operational_route_pattern_id
left join atlas.work_items wi on wi.id=r.work_item_id
left join atlas.work_execution_plans ep on ep.id=r.work_execution_plan_id;

comment on view atlas.v_operational_route_execution_position_v1 is
  'Read projection showing whether a route is Company Work-backed, externally sourced, or legacy-direct without creating a competing responsibility or worker-planning authority.';

alter table atlas.operational_route_patterns enable row level security;
alter table atlas.operational_route_pattern_stops enable row level security;
revoke all on atlas.operational_route_patterns from anon,authenticated;
revoke all on atlas.operational_route_pattern_stops from anon,authenticated;
revoke all on atlas.v_operational_route_execution_position_v1 from anon,authenticated;
grant select,insert,update,delete on atlas.operational_route_patterns to service_role;
grant select,insert,update,delete on atlas.operational_route_pattern_stops to service_role;
grant select on atlas.v_operational_route_execution_position_v1 to service_role;

revoke all on function atlas.guard_operational_route_pattern_scope_v1() from public,anon,authenticated;
revoke all on function atlas.guard_operational_route_company_work_scope_v1() from public,anon,authenticated;
revoke all on function atlas.materialize_operational_route_pattern_for_company_work_self_v1(uuid,uuid,text,jsonb) from public,anon;
grant execute on function atlas.materialize_operational_route_pattern_for_company_work_self_v1(uuid,uuid,text,jsonb) to authenticated,service_role;

COMMIT;
