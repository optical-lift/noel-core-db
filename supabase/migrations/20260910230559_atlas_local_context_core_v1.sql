create table local_intel.local_contexts (
  id uuid primary key default gen_random_uuid(),
  stable_key text not null unique,
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  organization_unit_id uuid references atlas.organization_units(id) on delete restrict,
  name text not null,
  status text not null default 'active',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table local_intel.local_contexts is 'Organization-owned Atlas Local world. V1 reuses discovery methods across customers; Local entity/data custody remains scoped to this context.';
comment on column local_intel.local_contexts.organization_id is 'Owning Atlas Organization.';
comment on column local_intel.local_contexts.organization_unit_id is 'Optional owning Operating Unit within the Organization. When present, it must belong to organization_id.';

create or replace function local_intel.enforce_local_context_owner_consistency()
returns trigger
language plpgsql
set search_path = pg_catalog, public, atlas, local_intel
as $$
begin
  if new.organization_unit_id is not null and not exists (
    select 1 from atlas.organization_units ou
    where ou.id = new.organization_unit_id
      and ou.organization_id = new.organization_id
  ) then
    raise exception 'organization_unit_id % does not belong to organization_id %', new.organization_unit_id, new.organization_id;
  end if;
  return new;
end;
$$;

create trigger local_context_owner_consistency
before insert or update of organization_id, organization_unit_id
on local_intel.local_contexts
for each row execute function local_intel.enforce_local_context_owner_consistency();

create index local_contexts_owner_idx on local_intel.local_contexts (organization_id, organization_unit_id, status);

create table local_intel.local_discovery_profiles (
  id uuid primary key default gen_random_uuid(),
  local_context_id uuid not null references local_intel.local_contexts(id) on delete restrict,
  stable_key text not null,
  name text not null,
  status text not null default 'active',
  territory_definition jsonb not null default '{}'::jsonb,
  entity_classes jsonb not null default '[]'::jsonb,
  relevance_criteria jsonb not null default '{}'::jsonb,
  source_strategy jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (local_context_id, stable_key)
);

comment on table local_intel.local_discovery_profiles is 'Organization-owned description of what Atlas Local should discover and maintain for a Local Context. Derived from the organization operating model; not a global industry taxonomy.';
create index local_discovery_profiles_context_status_idx on local_intel.local_discovery_profiles (local_context_id, status);

alter table local_intel.local_contexts enable row level security;
alter table local_intel.local_discovery_profiles enable row level security;
