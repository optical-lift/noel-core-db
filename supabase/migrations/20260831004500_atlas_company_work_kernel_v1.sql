-- Atlas Company Work Kernel v1
-- Governing direction: business requirement -> work -> allocation -> readiness/time/planning -> execution/result.
-- Clean cut: this migration does not backfill or depend on atlas.tasks.

begin;

create table if not exists atlas.work_requirements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  requirement_kind text not null default 'operational',
  summary text not null,
  source_object_type text,
  source_object_id uuid,
  state text not null default 'active'
    check (state in ('active','satisfied','cancelled','superseded')),
  established_at timestamptz not null default now(),
  requirement_began_at timestamptz,
  earliest_relevant_at timestamptz,
  latest_satisfactory_at timestamptz,
  consequence_of_delay jsonb not null default '{}'::jsonb,
  jurisdiction_key text,
  satisfied_at timestamptz,
  cancelled_at timestamptz,
  superseded_by_requirement_id uuid references atlas.work_requirements(id),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (latest_satisfactory_at is null or earliest_relevant_at is null or latest_satisfactory_at >= earliest_relevant_at),
  check ((state = 'satisfied') = (satisfied_at is not null) or state <> 'satisfied'),
  check ((state = 'cancelled') = (cancelled_at is not null) or state <> 'cancelled')
);

comment on table atlas.work_requirements is
  'Organization-owned requirement truth. A requirement exists independently of assignment, readiness, Day, Clock, or UI presentation.';

create index if not exists work_requirements_org_state_idx
  on atlas.work_requirements (organization_id, state);
create index if not exists work_requirements_org_latest_idx
  on atlas.work_requirements (organization_id, latest_satisfactory_at)
  where state = 'active';
create index if not exists work_requirements_source_idx
  on atlas.work_requirements (source_object_type, source_object_id)
  where source_object_type is not null and source_object_id is not null;

create table if not exists atlas.work_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  work_definition_id uuid references atlas.work_definitions(id),
  title text not null,
  instructions text,
  work_state text not null default 'open'
    check (work_state in ('open','completed','cancelled','superseded')),
  operation_class text,
  jurisdiction_key text,
  source_object_type text,
  source_object_id uuid,
  result_contract_key text,
  created_by_user_id uuid,
  completed_at timestamptz,
  cancelled_at timestamptz,
  superseded_by_work_item_id uuid references atlas.work_items(id),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (completed_at is null or work_state = 'completed'),
  check (cancelled_at is null or work_state = 'cancelled'),
  check (superseded_by_work_item_id is null or work_state = 'superseded')
);

comment on table atlas.work_items is
  'Canonical company work identity. Work existence is independent of assignee, readiness, planning horizon, Clock placement, and attention.';

create index if not exists work_items_org_state_idx
  on atlas.work_items (organization_id, work_state);
create index if not exists work_items_org_definition_idx
  on atlas.work_items (organization_id, work_definition_id)
  where work_definition_id is not null;
create index if not exists work_items_source_idx
  on atlas.work_items (source_object_type, source_object_id)
  where source_object_type is not null and source_object_id is not null;

create table if not exists atlas.work_requirement_links (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  requirement_id uuid not null references atlas.work_requirements(id) on delete cascade,
  work_item_id uuid not null references atlas.work_items(id) on delete cascade,
  link_role text not null
    check (link_role in ('advances','resolves','investigates','enables','protects')),
  active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (requirement_id, work_item_id, link_role)
);

comment on table atlas.work_requirement_links is
  'Explicit relation between business requirement truth and concrete work. Replaces causal misuse of parent-task visibility structure.';

create index if not exists work_requirement_links_requirement_idx
  on atlas.work_requirement_links (organization_id, requirement_id)
  where active;
create index if not exists work_requirement_links_work_idx
  on atlas.work_requirement_links (organization_id, work_item_id)
  where active;

create table if not exists atlas.work_allocations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  work_item_id uuid not null references atlas.work_items(id) on delete cascade,
  assignee_membership_id uuid not null references atlas.organization_memberships(id),
  assigned_by_membership_id uuid references atlas.organization_memberships(id),
  allocation_role text not null default 'responsible'
    check (allocation_role in ('responsible','participant','approver')),
  state text not null default 'active'
    check (state in ('active','released','completed')),
  allocated_at timestamptz not null default now(),
  released_at timestamptz,
  release_reason text,
  completed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (released_at is null or state = 'released'),
  check (completed_at is null or state = 'completed')
);

comment on table atlas.work_allocations is
  'Custody history for company work. Assignment is downstream of work identity. organization_memberships is the transitional institutional-seat carrier.';

create unique index if not exists work_allocations_one_active_responsible_idx
  on atlas.work_allocations (work_item_id)
  where state = 'active' and allocation_role = 'responsible';
create index if not exists work_allocations_assignee_active_idx
  on atlas.work_allocations (organization_id, assignee_membership_id, state);
create index if not exists work_allocations_work_history_idx
  on atlas.work_allocations (work_item_id, allocated_at);

create table if not exists atlas.work_item_relations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  from_work_item_id uuid not null references atlas.work_items(id) on delete cascade,
  to_work_item_id uuid not null references atlas.work_items(id) on delete cascade,
  relation_kind text not null
    check (relation_kind in ('blocks','enables','depends_on','part_of','alternative_to','handoff_to')),
  active boolean not null default true,
  satisfied_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (from_work_item_id <> to_work_item_id),
  unique (from_work_item_id, to_work_item_id, relation_kind)
);

comment on table atlas.work_item_relations is
  'Explicit causal/structural relations between work items. Relations do not imply visibility inheritance.';

create index if not exists work_item_relations_from_idx
  on atlas.work_item_relations (organization_id, from_work_item_id)
  where active;
create index if not exists work_item_relations_to_idx
  on atlas.work_item_relations (organization_id, to_work_item_id)
  where active;

create table if not exists atlas.work_time_contracts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  work_item_id uuid not null references atlas.work_items(id) on delete cascade,
  contract_state text not null default 'active'
    check (contract_state in ('active','superseded','satisfied','cancelled')),
  earliest_lawful_at timestamptz,
  preferred_start_at timestamptz,
  preferred_end_at timestamptz,
  latest_lawful_at timestamptz,
  hard_finish_at timestamptz,
  expected_duration_minutes integer check (expected_duration_minutes is null or expected_duration_minutes >= 0),
  minimum_duration_minutes integer check (minimum_duration_minutes is null or minimum_duration_minutes >= 0),
  maximum_duration_minutes integer check (maximum_duration_minutes is null or maximum_duration_minutes >= 0),
  movement_policy text not null default 'movable'
    check (movement_policy in ('fixed','bounded','movable','unplaced')),
  consequence_of_delay jsonb not null default '{}'::jsonb,
  source_kind text,
  source_id uuid,
  source_confidence numeric check (source_confidence is null or (source_confidence >= 0 and source_confidence <= 1)),
  superseded_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (preferred_end_at is null or preferred_start_at is null or preferred_end_at >= preferred_start_at),
  check (latest_lawful_at is null or earliest_lawful_at is null or latest_lawful_at >= earliest_lawful_at),
  check (hard_finish_at is null or earliest_lawful_at is null or hard_finish_at >= earliest_lawful_at),
  check (maximum_duration_minutes is null or minimum_duration_minutes is null or maximum_duration_minutes >= minimum_duration_minutes)
);

comment on table atlas.work_time_contracts is
  'Authoritative time truth for work, separate from week/day admission and Clock choreography.';

create unique index if not exists work_time_contracts_one_active_idx
  on atlas.work_time_contracts (work_item_id)
  where contract_state = 'active';
create index if not exists work_time_contracts_org_boundary_idx
  on atlas.work_time_contracts (organization_id, hard_finish_at)
  where contract_state = 'active';

create table if not exists atlas.work_planning_conflicts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  work_item_id uuid not null references atlas.work_items(id) on delete cascade,
  allocation_id uuid references atlas.work_allocations(id) on delete set null,
  conflict_kind text not null
    check (conflict_kind in (
      'no_eligible_assignee',
      'resource_unavailable',
      'dependency_unresolved',
      'location_or_travel_conflict',
      'insufficient_capacity',
      'hard_boundary_unfit',
      'time_contract_incomplete',
      'other'
    )),
  detected_at timestamptz not null default now(),
  horizon_start timestamptz,
  horizon_end timestamptz,
  required_by timestamptz,
  capacity_snapshot jsonb not null default '{}'::jsonb,
  reason text not null,
  state text not null default 'open'
    check (state in ('open','resolved','accepted')),
  resolution_kind text,
  resolution_note text,
  resolved_at timestamptz,
  resolved_by_membership_id uuid references atlas.organization_memberships(id),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (horizon_end is null or horizon_start is null or horizon_end >= horizon_start),
  check (resolved_at is null or state in ('resolved','accepted'))
);

comment on table atlas.work_planning_conflicts is
  'Explicit operational truth when Atlas cannot reconcile open work with allocation, readiness, resources, travel, capacity, or a hard temporal boundary.';

create index if not exists work_planning_conflicts_org_state_idx
  on atlas.work_planning_conflicts (organization_id, state, detected_at);
create index if not exists work_planning_conflicts_work_idx
  on atlas.work_planning_conflicts (work_item_id, state);

-- New kernel is server-owned until canonical RPC/API authorization is added.
-- Do not accidentally expose direct table access while the UI contract is still being built.
revoke all on table atlas.work_requirements from anon, authenticated;
revoke all on table atlas.work_items from anon, authenticated;
revoke all on table atlas.work_requirement_links from anon, authenticated;
revoke all on table atlas.work_allocations from anon, authenticated;
revoke all on table atlas.work_item_relations from anon, authenticated;
revoke all on table atlas.work_time_contracts from anon, authenticated;
revoke all on table atlas.work_planning_conflicts from anon, authenticated;

grant select, insert, update, delete on table atlas.work_requirements to service_role;
grant select, insert, update, delete on table atlas.work_items to service_role;
grant select, insert, update, delete on table atlas.work_requirement_links to service_role;
grant select, insert, update, delete on table atlas.work_allocations to service_role;
grant select, insert, update, delete on table atlas.work_item_relations to service_role;
grant select, insert, update, delete on table atlas.work_time_contracts to service_role;
grant select, insert, update, delete on table atlas.work_planning_conflicts to service_role;

commit;
