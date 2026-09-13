-- Atlas First-Class Ledger v1.
-- Establishes canonical Ledger identity, automatic governing-Ledger birth for every Organization,
-- explicit Principal -> Ledger root authority, and compatibility attachment for current
-- organization-scoped Ledger reality.

BEGIN;

create table atlas.ledgers (
  id uuid primary key default gen_random_uuid(),
  stable_key text not null unique,
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  ledger_kind text not null default 'organization_governing'
    check (ledger_kind = 'organization_governing'),
  status text not null default 'active'
    check (status in ('active','retired')),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id),
  unique (id, organization_id)
);

alter table atlas.ledgers enable row level security;
revoke all on atlas.ledgers from anon, authenticated;

create trigger ledgers_set_updated_at
before update on atlas.ledgers
for each row execute function atlas.set_updated_at();

-- Governing Ledger birth is an institutional invariant, not a responsibility of any
-- particular UI/RPC/commercial flow. Every future Organization insert therefore creates
-- its governing Ledger in the same transaction, including legacy creation paths that
-- have not yet been migrated to the Person-first establishment contract.
create or replace function atlas.establish_governing_ledger_on_organization_insert_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
begin
  insert into atlas.ledgers (
    stable_key,
    organization_id,
    ledger_kind,
    status,
    metadata
  ) values (
    new.stable_key,
    new.id,
    'organization_governing',
    'active',
    jsonb_build_object(
      'scope_state','canonical',
      'establishment_basis','organization_birth'
    )
  )
  on conflict (organization_id) do nothing;

  return new;
end;
$function$;

revoke all on function atlas.establish_governing_ledger_on_organization_insert_v1()
  from public, anon, authenticated;

create trigger organizations_establish_governing_ledger_v1
after insert on atlas.organizations
for each row execute function atlas.establish_governing_ledger_on_organization_insert_v1();

-- Backfill Organizations that predate first-class Ledger identity. The historical
-- Feast Guild scope is deliberately marked mixed pending later adjudication.
insert into atlas.ledgers (
  stable_key,
  organization_id,
  ledger_kind,
  status,
  metadata
)
select
  o.stable_key,
  o.id,
  'organization_governing',
  'active',
  case
    when o.stable_key = 'feast_guild' then
      jsonb_build_object(
        'scope_state','legacy_mixed_pending_adjudication',
        'establishment_basis','legacy_organization_scope_backfill',
        'adjudication_reason','Historical Feast Guild organization scope currently contains Elm / Waiting Room Farm institutional reality.'
      )
    else
      jsonb_build_object(
        'scope_state','canonical',
        'establishment_basis','legacy_organization_scope_backfill'
      )
  end
from atlas.organizations o;

create or replace function atlas.primary_ledger_for_organization_v1(
  p_organization_id uuid
)
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, atlas
as $function$
  select l.id
  from atlas.ledgers l
  where l.organization_id = p_organization_id
    and l.ledger_kind = 'organization_governing'
    and l.status = 'active'
  limit 1;
$function$;

revoke all on function atlas.primary_ledger_for_organization_v1(uuid)
  from public, anon, authenticated;

alter table atlas.organization_ledger_entries
  add column ledger_id uuid;

update atlas.organization_ledger_entries e
set ledger_id = l.id
from atlas.ledgers l
where l.organization_id = e.organization_id
  and l.ledger_kind = 'organization_governing'
  and l.status = 'active'
  and e.ledger_id is null;

alter table atlas.organization_ledger_entries
  alter column ledger_id set not null;

alter table atlas.organization_ledger_entries
  add constraint organization_ledger_entries_ledger_organization_fk
  foreign key (ledger_id, organization_id)
  references atlas.ledgers(id, organization_id)
  on delete restrict;

create index organization_ledger_entries_ledger_revision_idx
  on atlas.organization_ledger_entries (ledger_id, revision);

alter table atlas.ledger_entitlement_bindings
  add column ledger_id uuid references atlas.ledgers(id) on delete restrict;

update atlas.ledger_entitlement_bindings b
set ledger_id = l.id
from atlas.ledgers l
where b.organization_id is not null
  and l.organization_id = b.organization_id
  and l.ledger_kind = 'organization_governing'
  and l.status = 'active'
  and b.ledger_id is null;

create index ledger_entitlement_bindings_ledger_idx
  on atlas.ledger_entitlement_bindings (ledger_id)
  where ledger_id is not null;

create or replace function atlas.organization_ledger_scope_compatibility_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_expected_ledger_id uuid;
begin
  if new.organization_id is null then
    if new.ledger_id is not null then
      raise exception 'Ledger cannot be assigned without Organization scope.' using errcode = '23514';
    end if;
    return new;
  end if;

  v_expected_ledger_id := atlas.primary_ledger_for_organization_v1(new.organization_id);

  if v_expected_ledger_id is null then
    raise exception 'Organization has no active governing Ledger.' using errcode = '23514';
  end if;

  if new.ledger_id is null then
    new.ledger_id := v_expected_ledger_id;
  elsif new.ledger_id <> v_expected_ledger_id then
    raise exception 'Organization / Ledger scope contradiction.' using errcode = '23514';
  end if;

  return new;
end;
$function$;

revoke all on function atlas.organization_ledger_scope_compatibility_v1()
  from public, anon, authenticated;

drop trigger if exists organization_ledger_entries_ledger_scope_v1
  on atlas.organization_ledger_entries;
create trigger organization_ledger_entries_ledger_scope_v1
before insert or update of organization_id, ledger_id
on atlas.organization_ledger_entries
for each row execute function atlas.organization_ledger_scope_compatibility_v1();

drop trigger if exists ledger_entitlement_bindings_ledger_scope_v1
  on atlas.ledger_entitlement_bindings;
create trigger ledger_entitlement_bindings_ledger_scope_v1
before insert or update of organization_id, ledger_id
on atlas.ledger_entitlement_bindings
for each row execute function atlas.organization_ledger_scope_compatibility_v1();

create table atlas.principal_ledger_authorities (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid not null references atlas.principals(id) on delete restrict,
  ledger_id uuid not null references atlas.ledgers(id) on delete restrict,
  authority_kind text not null default 'root_governing'
    check (authority_kind = 'root_governing'),
  status text not null default 'active'
    check (status in ('active','ended')),
  basis text not null
    check (btrim(basis) <> ''),
  established_at timestamptz not null default now(),
  ended_at timestamptz,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (status = 'active' and ended_at is null)
    or
    (status = 'ended' and ended_at is not null)
  )
);

create unique index principal_ledger_authorities_active_uq
  on atlas.principal_ledger_authorities (principal_id, ledger_id, authority_kind)
  where status = 'active';

create index principal_ledger_authorities_ledger_active_idx
  on atlas.principal_ledger_authorities (ledger_id, principal_id)
  where status = 'active';

alter table atlas.principal_ledger_authorities enable row level security;
revoke all on atlas.principal_ledger_authorities from anon, authenticated;

create trigger principal_ledger_authorities_set_updated_at
before update on atlas.principal_ledger_authorities
for each row execute function atlas.set_updated_at();

insert into atlas.principal_ledger_authorities (
  principal_id,
  ledger_id,
  authority_kind,
  status,
  basis,
  metadata
)
select
  p.id,
  l.id,
  'root_governing',
  'active',
  'legacy_principal_organization_compatibility',
  jsonb_build_object(
    'sourcePrincipalOrganizationId',p.organization_id,
    'establishmentBasis','first_class_ledger_v1_backfill'
  )
from atlas.principals p
join atlas.ledgers l
  on l.organization_id = p.organization_id
 and l.ledger_kind = 'organization_governing'
 and l.status = 'active'
where p.status = 'active'
  and p.organization_id is not null;

create or replace function atlas.principal_has_ledger_authority_v1(
  p_principal_id uuid,
  p_ledger_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, atlas
as $function$
  select exists (
    select 1
    from atlas.principal_ledger_authorities a
    join atlas.ledgers l on l.id = a.ledger_id
    where a.principal_id = p_principal_id
      and a.ledger_id = p_ledger_id
      and a.authority_kind = 'root_governing'
      and a.status = 'active'
      and l.status = 'active'
  );
$function$;

revoke all on function atlas.principal_has_ledger_authority_v1(uuid,uuid)
  from public, anon, authenticated;

create or replace function atlas.principal_ledgers_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_principal_id uuid;
  v_items jsonb;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode = '42501';
  end if;

  v_principal_id := atlas.current_principal_id_v1();

  if v_principal_id is null then
    return jsonb_build_object(
      'contractVersion','principal_ledgers_self_v1',
      'state','principal_required',
      'items','[]'::jsonb
    );
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'ledgerId',l.id,
        'ledgerStableKey',l.stable_key,
        'ledgerKind',l.ledger_kind,
        'ledgerStatus',l.status,
        'organizationId',o.id,
        'organizationStableKey',o.stable_key,
        'organizationName',o.name,
        'authorityKind',a.authority_kind,
        'scopeState',coalesce(l.metadata->>'scope_state','canonical')
      ) order by o.name, l.stable_key
    ),
    '[]'::jsonb
  )
  into v_items
  from atlas.principal_ledger_authorities a
  join atlas.ledgers l
    on l.id = a.ledger_id
   and l.status = 'active'
  join atlas.organizations o
    on o.id = l.organization_id
   and o.status = 'active'
  where a.principal_id = v_principal_id
    and a.status = 'active'
    and a.authority_kind = 'root_governing';

  return jsonb_build_object(
    'contractVersion','principal_ledgers_self_v1',
    'state','ready',
    'principalId',v_principal_id,
    'items',v_items
  );
end;
$function$;

revoke all on function atlas.principal_ledgers_self_api_v1()
  from public, anon;
grant execute on function atlas.principal_ledgers_self_api_v1()
  to authenticated;

COMMIT;
