begin;

-- Shared Intelligence v1: decouple contextual relevance from canonical external identity.
--
-- This migration is deliberately additive. local_intel.entities.local_context_id remains
-- in place as a compatibility/discovery-origin pointer while existing readers and writers
-- transition to the non-exclusive membership relation below.

create table local_intel.entity_context_memberships (
  id uuid primary key default gen_random_uuid(),
  entity_id uuid not null references local_intel.entities(id) on delete cascade,
  local_context_id uuid not null references local_intel.local_contexts(id) on delete restrict,
  membership_kind text not null default 'known_in',
  status text not null default 'active',
  basis text not null default 'explicit',
  source_id uuid references local_intel.sources(id) on delete set null,
  verification_state text not null default 'derived',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint entity_context_memberships_entity_context_uq unique (entity_id, local_context_id),
  constraint entity_context_memberships_membership_kind_nonblank check (btrim(membership_kind) <> ''),
  constraint entity_context_memberships_status_check check (status in ('active','inactive')),
  constraint entity_context_memberships_basis_nonblank check (btrim(basis) <> ''),
  constraint entity_context_memberships_verification_state_nonblank check (btrim(verification_state) <> ''),
  constraint entity_context_memberships_metadata_object check (jsonb_typeof(metadata) = 'object')
);

create index entity_context_memberships_context_status_idx
  on local_intel.entity_context_memberships(local_context_id, status, entity_id);

create index entity_context_memberships_entity_status_idx
  on local_intel.entity_context_memberships(entity_id, status, local_context_id);

comment on table local_intel.entity_context_memberships is
  'Non-exclusive contextual relevance for canonical external-world entities. A Local context may know, discover, curate, or use an entity without owning or cloning that entity identity.';

comment on column local_intel.entity_context_memberships.entity_id is
  'Canonical external-world entity. The same entity_id may be relevant to multiple Local contexts.';

comment on column local_intel.entity_context_memberships.local_context_id is
  'Context in which the canonical entity is known or relevant; not an identity namespace.';

comment on column local_intel.entity_context_memberships.basis is
  'Why the entity/context membership exists. This describes contextual admission, not the entity identity itself.';

alter table local_intel.entity_context_memberships enable row level security;

-- Match inherited local_intel custody: no direct application-role table surface.
revoke all on table local_intel.entity_context_memberships from anon, authenticated, service_role;

insert into local_intel.entity_context_memberships (
  entity_id,
  local_context_id,
  membership_kind,
  status,
  basis,
  verification_state,
  metadata
)
select
  e.id,
  e.local_context_id,
  'known_in',
  'active',
  'legacy_entities_local_context_id',
  'derived',
  jsonb_build_object(
    'legacyCompatibility', true,
    'sourceColumn', 'local_intel.entities.local_context_id',
    'migration', 'local_intel_shared_entity_context_membership_v1'
  )
from local_intel.entities e
on conflict (entity_id, local_context_id) do nothing;

create or replace function local_intel.touch_entity_context_membership_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'local_intel'
as $function$
begin
  new.updated_at := now();
  return new;
end;
$function$;

revoke all on function local_intel.touch_entity_context_membership_v1() from public;

create trigger entity_context_memberships_touch_v1
before update on local_intel.entity_context_memberships
for each row execute function local_intel.touch_entity_context_membership_v1();

create or replace function local_intel.sync_entity_context_membership_from_legacy_pointer_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'local_intel'
as $function$
begin
  insert into local_intel.entity_context_memberships as existing (
    entity_id,
    local_context_id,
    membership_kind,
    status,
    basis,
    verification_state,
    metadata
  ) values (
    new.id,
    new.local_context_id,
    'known_in',
    'active',
    'legacy_entities_local_context_id',
    'derived',
    jsonb_build_object(
      'legacyCompatibility', true,
      'sourceColumn', 'local_intel.entities.local_context_id',
      'syncFunction', 'sync_entity_context_membership_from_legacy_pointer_v1'
    )
  )
  on conflict (entity_id, local_context_id) do update
    set status = 'active',
        metadata = existing.metadata || excluded.metadata,
        updated_at = now();

  return new;
end;
$function$;

revoke all on function local_intel.sync_entity_context_membership_from_legacy_pointer_v1() from public;

create trigger entities_context_membership_compatibility_v1
after insert or update of local_context_id on local_intel.entities
for each row execute function local_intel.sync_entity_context_membership_from_legacy_pointer_v1();

comment on table local_intel.entities is
  'Canonical Shared Intelligence representation of an external-world referent. Contextual relevance belongs in entity_context_memberships; local_context_id is retained temporarily for inherited compatibility and discovery-origin semantics.';

comment on column local_intel.entities.local_context_id is
  'Legacy compatibility/discovery-origin pointer. It must not be interpreted as ownership of the entity identity. Non-exclusive contextual relevance belongs in local_intel.entity_context_memberships.';

commit;
