-- Atlas Organization Unit Custody v1
-- Separates institutional custody from a Principal's portfolio lens and from human assignment.
-- Organization = durable tenant/institution.
-- Organization Unit = durable operating body/site/business inside the institution.
-- Portfolio Unit = a Principal planning lens that may point at an Organization Unit.

begin;

create table if not exists atlas.organization_units (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  parent_unit_id uuid,
  stable_key text not null,
  name text not null,
  unit_kind text not null default 'operating_unit',
  status text not null default 'active'
    check (status in ('active','inactive','archived')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(stable_key) <> ''),
  check (btrim(name) <> ''),
  check (btrim(unit_kind) <> ''),
  check (parent_unit_id is null or parent_unit_id <> id),
  unique (organization_id, stable_key)
);

comment on table atlas.organization_units is
  'Durable institutional operating units inside an organization. Units belong to the institution, not to a person, assignee, portal, or Principal portfolio.';
comment on column atlas.organization_units.organization_id is
  'Institutional custody root. The organization remains the tenant/company boundary.';
comment on column atlas.organization_units.parent_unit_id is
  'Optional institutional hierarchy for branches, sites, departments, programs, properties, or other nested operating bodies.';
comment on column atlas.organization_units.unit_kind is
  'Open classification vocabulary. Atlas core does not restrict industries to farm-specific unit kinds.';

create unique index if not exists organization_units_org_id_identity_idx
  on atlas.organization_units (organization_id, id);
create index if not exists organization_units_org_status_idx
  on atlas.organization_units (organization_id, status, name);
create index if not exists organization_units_parent_idx
  on atlas.organization_units (organization_id, parent_unit_id)
  where parent_unit_id is not null;

alter table atlas.organization_units
  drop constraint if exists organization_units_parent_org_fk,
  add constraint organization_units_parent_org_fk
    foreign key (organization_id, parent_unit_id)
    references atlas.organization_units (organization_id, id)
    on delete restrict;

-- Existing farms are domain objects. Give each current farm a durable institutional unit
-- without making the neutral Organization Unit kernel depend on farm semantics.
insert into atlas.organization_units (
  organization_id,
  stable_key,
  name,
  unit_kind,
  status,
  metadata
)
select
  f.organization_id,
  f.stable_key,
  f.name,
  'farm',
  case when f.status = 'active' then 'active' else 'inactive' end,
  jsonb_build_object(
    'created_from','organization_unit_custody_v1',
    'domain_adapter','atlas.farms',
    'farm_id',f.id
  )
from atlas.farms f
on conflict (organization_id, stable_key) do update
set name = excluded.name,
    metadata = atlas.organization_units.metadata || excluded.metadata,
    updated_at = now();

alter table atlas.farms
  add column if not exists organization_unit_id uuid;

update atlas.farms f
set organization_unit_id = u.id
from atlas.organization_units u
where u.organization_id = f.organization_id
  and u.stable_key = f.stable_key
  and f.organization_unit_id is null;

alter table atlas.farms
  drop constraint if exists farms_organization_unit_org_fk,
  add constraint farms_organization_unit_org_fk
    foreign key (organization_id, organization_unit_id)
    references atlas.organization_units (organization_id, id)
    on delete restrict;

create unique index if not exists farms_one_organization_unit_idx
  on atlas.farms (organization_unit_id)
  where organization_unit_id is not null;

comment on column atlas.farms.organization_unit_id is
  'Institutional operating-unit identity for this farm domain object. Farm truth is scoped through the unit but the unit is not farm-specific.';

-- Preserve the Principal portfolio as a lens, but make its institutional referent explicit.
alter table atlas.portfolio_units
  add column if not exists organization_unit_id uuid;

update atlas.portfolio_units pu
set organization_unit_id = f.organization_unit_id
from atlas.farms f
where pu.linked_farm_id = f.id
  and pu.organization_id = f.organization_id
  and pu.organization_unit_id is null;

alter table atlas.portfolio_units
  drop constraint if exists portfolio_units_organization_unit_org_fk,
  add constraint portfolio_units_organization_unit_org_fk
    foreign key (organization_id, organization_unit_id)
    references atlas.organization_units (organization_id, id)
    on delete restrict;

create index if not exists portfolio_units_organization_unit_idx
  on atlas.portfolio_units (organization_id, organization_unit_id)
  where organization_unit_id is not null;

comment on column atlas.portfolio_units.organization_unit_id is
  'Optional institutional referent for this Principal planning lens. The portfolio row does not own institutional reality.';

-- Company Work keeps organization custody and gains an optional operating-unit locus.
-- NULL means organization-wide work; a populated unit means the reality/work belongs to
-- that durable institutional unit inside the organization.
alter table atlas.work_requirements
  add column if not exists organization_unit_id uuid;

alter table atlas.work_requirements
  drop constraint if exists work_requirements_organization_unit_org_fk,
  add constraint work_requirements_organization_unit_org_fk
    foreign key (organization_id, organization_unit_id)
    references atlas.organization_units (organization_id, id)
    on delete restrict;

create index if not exists work_requirements_org_unit_state_idx
  on atlas.work_requirements (organization_id, organization_unit_id, state);

comment on column atlas.work_requirements.organization_unit_id is
  'Optional institutional operating-unit locus. Requirement existence remains independent of assignment, portal visibility, Day, Clock, or attention.';

alter table atlas.work_items
  add column if not exists organization_unit_id uuid;

alter table atlas.work_items
  drop constraint if exists work_items_organization_unit_org_fk,
  add constraint work_items_organization_unit_org_fk
    foreign key (organization_id, organization_unit_id)
    references atlas.organization_units (organization_id, id)
    on delete restrict;

create index if not exists work_items_org_unit_state_idx
  on atlas.work_items (organization_id, organization_unit_id, work_state);

comment on column atlas.work_items.organization_unit_id is
  'Optional institutional operating-unit locus for canonical company work. Allocation remains a separate downstream relation.';

create or replace view atlas.company_work_position_v2
with (security_invoker = true)
as
select
  p.organization_id,
  w.organization_unit_id,
  u.stable_key as organization_unit_key,
  u.name as organization_unit_name,
  u.unit_kind as organization_unit_kind,
  p.work_item_id,
  p.title,
  p.instructions,
  p.work_state,
  p.operation_class,
  p.jurisdiction_key,
  p.source_object_type,
  p.source_object_id,
  p.created_at,
  p.updated_at,
  p.responsible_allocation_id,
  p.assignee_membership_id,
  p.allocated_at,
  p.time_contract_id,
  p.earliest_lawful_at,
  p.preferred_start_at,
  p.preferred_end_at,
  p.latest_lawful_at,
  p.hard_finish_at,
  p.expected_duration_minutes,
  p.movement_policy,
  p.unresolved_dependency_count,
  p.open_planning_conflict_id,
  p.open_planning_conflict_kind,
  p.open_planning_conflict_reason,
  p.conflict_required_by,
  p.management_position
from atlas.company_work_position_v1 p
join atlas.work_items w
  on w.organization_id = p.organization_id
 and w.id = p.work_item_id
left join atlas.organization_units u
  on u.organization_id = w.organization_id
 and u.id = w.organization_unit_id;

comment on view atlas.company_work_position_v2 is
  'Complete canonical company-work position with institutional operating-unit scope. Person portals and allocations remain projections over this company truth.';

revoke all on atlas.company_work_position_v2 from public, anon, authenticated;
grant select on atlas.company_work_position_v2 to service_role;

create or replace function atlas.company_work_position_api_v2(
  p_organization_id uuid,
  p_organization_unit_id uuid default null
)
returns table (
  organization_id uuid,
  organization_unit_id uuid,
  organization_unit_key text,
  organization_unit_name text,
  organization_unit_kind text,
  work_item_id uuid,
  title text,
  instructions text,
  work_state text,
  operation_class text,
  jurisdiction_key text,
  source_object_type text,
  source_object_id uuid,
  created_at timestamptz,
  updated_at timestamptz,
  responsible_allocation_id uuid,
  assignee_membership_id uuid,
  allocated_at timestamptz,
  time_contract_id uuid,
  earliest_lawful_at timestamptz,
  preferred_start_at timestamptz,
  preferred_end_at timestamptz,
  latest_lawful_at timestamptz,
  hard_finish_at timestamptz,
  expected_duration_minutes integer,
  movement_policy text,
  unresolved_dependency_count integer,
  open_planning_conflict_id uuid,
  open_planning_conflict_kind text,
  open_planning_conflict_reason text,
  conflict_required_by timestamptz,
  management_position text
)
language plpgsql
stable
security definer
set search_path = atlas, auth, public
as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from atlas.organization_memberships om
    where om.organization_id = p_organization_id
      and om.user_id = auth.uid()
      and om.active
      and om.role = 'owner'
  ) then
    raise exception 'Active organization-owner access is required.' using errcode = '42501';
  end if;

  if p_organization_unit_id is not null and not exists (
    select 1
    from atlas.organization_units ou
    where ou.organization_id = p_organization_id
      and ou.id = p_organization_unit_id
  ) then
    raise exception 'Organization Unit does not belong to this organization.' using errcode = '22023';
  end if;

  return query
  select
    p.organization_id,
    p.organization_unit_id,
    p.organization_unit_key,
    p.organization_unit_name,
    p.organization_unit_kind,
    p.work_item_id,
    p.title,
    p.instructions,
    p.work_state,
    p.operation_class,
    p.jurisdiction_key,
    p.source_object_type,
    p.source_object_id,
    p.created_at,
    p.updated_at,
    p.responsible_allocation_id,
    p.assignee_membership_id,
    p.allocated_at,
    p.time_contract_id,
    p.earliest_lawful_at,
    p.preferred_start_at,
    p.preferred_end_at,
    p.latest_lawful_at,
    p.hard_finish_at,
    p.expected_duration_minutes,
    p.movement_policy,
    p.unresolved_dependency_count,
    p.open_planning_conflict_id,
    p.open_planning_conflict_kind,
    p.open_planning_conflict_reason,
    p.conflict_required_by,
    p.management_position
  from atlas.company_work_position_v2 p
  where p.organization_id = p_organization_id
    and (p_organization_unit_id is null or p.organization_unit_id = p_organization_unit_id)
  order by
    case p.management_position
      when 'planning_conflict' then 1
      when 'unassigned' then 2
      when 'waiting_dependency' then 3
      when 'allocated' then 4
      else 5
    end,
    p.hard_finish_at nulls last,
    p.created_at,
    p.work_item_id;
end;
$$;

comment on function atlas.company_work_position_api_v2(uuid, uuid) is
  'Owner-authorized Company Work reader with optional institutional operating-unit scope. NULL unit returns the complete organization position, including organization-wide work.';

revoke all on function atlas.company_work_position_api_v2(uuid, uuid) from public, anon;
grant execute on function atlas.company_work_position_api_v2(uuid, uuid) to authenticated, service_role;

-- Organization Units are server-owned until a member-facing jurisdiction membrane is added.
revoke all on table atlas.organization_units from public, anon, authenticated;
grant select, insert, update, delete on table atlas.organization_units to service_role;

-- Migration invariants: every existing farm must now have one institutional unit, and
-- any farm-backed Principal portfolio lens must resolve to that same unit.
do $$
begin
  if exists (
    select 1
    from atlas.farms f
    where f.organization_unit_id is null
  ) then
    raise exception 'Organization Unit backfill left an existing farm without institutional custody.';
  end if;

  if exists (
    select 1
    from atlas.portfolio_units pu
    join atlas.farms f on f.id = pu.linked_farm_id
    where pu.organization_unit_id is distinct from f.organization_unit_id
  ) then
    raise exception 'Principal portfolio lens does not match its linked farm Organization Unit.';
  end if;
end;
$$;

commit;
