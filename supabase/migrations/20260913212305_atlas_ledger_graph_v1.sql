-- Atlas Ledger Graph v1.
-- Generalizes Ledger identity from one-Organization/one-Ledger compatibility into an
-- independent governed graph with explicit Organization participation, Ledger relationships,
-- cross-Ledger correlations, and direct many-to-many Principal authority.

BEGIN;

-- Opaque institutional keys are identifiers, not names/slugs.
create or replace function atlas.new_opaque_stable_key_v1()
returns text
language sql
volatile
security definer
set search_path = pg_catalog
as $function$
  select lower(replace(gen_random_uuid()::text,'-',''));
$function$;

revoke all on function atlas.new_opaque_stable_key_v1()
  from public, anon, authenticated;
grant execute on function atlas.new_opaque_stable_key_v1()
  to service_role;

-- Remove the transitional universal Organization -> one governing Ledger birth invariant.
drop trigger if exists organizations_establish_governing_ledger_v1
  on atlas.organizations;
drop function if exists atlas.establish_governing_ledger_on_organization_insert_v1();

-- organization_ledger_entries used the old composite ownership identity. Preserve its
-- Organization scope, but make Ledger identity independent and validate the relationship
-- through the participation graph instead.
alter table atlas.organization_ledger_entries
  drop constraint if exists organization_ledger_entries_ledger_organization_fk;

alter table atlas.ledgers
  add column name text;

update atlas.ledgers l
set name = coalesce(o.name,l.stable_key)
from atlas.organizations o
where o.id = l.organization_id
  and l.name is null;

update atlas.ledgers
set name = stable_key
where name is null;

alter table atlas.ledgers
  alter column name set not null;

alter table atlas.ledgers
  add constraint ledgers_name_nonempty_check
  check (btrim(name) <> '');

alter table atlas.ledgers
  drop constraint if exists ledgers_organization_id_key,
  drop constraint if exists ledgers_id_organization_id_key,
  drop constraint if exists ledgers_ledger_kind_check;

alter table atlas.ledgers
  alter column organization_id drop not null,
  alter column ledger_kind set default 'governed_reality';

alter table atlas.ledgers
  add constraint ledgers_ledger_kind_nonempty_check
  check (btrim(ledger_kind) <> '');

comment on column atlas.ledgers.organization_id is
  'Legacy compatibility/provenance link only. Canonical Organization <-> Ledger association lives in atlas.ledger_organization_participations.';

-- Explicit Organization <-> Ledger graph participation. Multiple relationship kinds may
-- exist for the same pair. is_compatibility_primary exists only to support old surfaces
-- that still need one default Ledger for an Organization; it is not an ownership law.
create table atlas.ledger_organization_participations (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references atlas.ledgers(id) on delete restrict,
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  participation_kind text not null
    check (btrim(participation_kind) <> ''),
  is_compatibility_primary boolean not null default false,
  status text not null default 'active'
    check (status in ('active','ended')),
  basis jsonb not null default '{}'::jsonb
    check (jsonb_typeof(basis) = 'object'),
  established_at timestamptz not null default now(),
  ended_at timestamptz,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (status='active' and ended_at is null)
    or
    (status='ended' and ended_at is not null)
  )
);

create unique index ledger_organization_participations_active_kind_uq
  on atlas.ledger_organization_participations
  (ledger_id,organization_id,participation_kind)
  where status='active';

create unique index ledger_organization_participations_one_primary_org_uq
  on atlas.ledger_organization_participations (organization_id)
  where status='active' and is_compatibility_primary;

create index ledger_organization_participations_ledger_active_idx
  on atlas.ledger_organization_participations (ledger_id,organization_id)
  where status='active';

alter table atlas.ledger_organization_participations enable row level security;
revoke all on atlas.ledger_organization_participations from anon, authenticated;

create trigger ledger_organization_participations_set_updated_at
before update on atlas.ledger_organization_participations
for each row execute function atlas.set_updated_at();

-- Preserve every historical Organization/Ledger association as explicit graph evidence.
insert into atlas.ledger_organization_participations (
  ledger_id,
  organization_id,
  participation_kind,
  is_compatibility_primary,
  status,
  basis,
  ended_at,
  metadata
)
select
  l.id,
  l.organization_id,
  'governing',
  true,
  case when l.status='active' then 'active' else 'ended' end,
  jsonb_build_object(
    'source','ledger_graph_v1_backfill',
    'legacyLedgerOrganizationId',l.organization_id,
    'legacyLedgerStableKey',l.stable_key
  ),
  case when l.status='active' then null else now() end,
  jsonb_build_object(
    'legacyCompatibility',true,
    'scopeState',coalesce(l.metadata->>'scope_state','canonical')
  )
from atlas.ledgers l
where l.organization_id is not null;

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
  from atlas.ledger_organization_participations p
  join atlas.ledgers l on l.id=p.ledger_id
  where p.organization_id=p_organization_id
    and p.status='active'
    and p.is_compatibility_primary
    and l.status='active'
  limit 1;
$function$;

revoke all on function atlas.primary_ledger_for_organization_v1(uuid)
  from public, anon, authenticated;
grant execute on function atlas.primary_ledger_for_organization_v1(uuid)
  to service_role;

create or replace function atlas.establish_ledger_organization_participation_v1(
  p_ledger_id uuid,
  p_organization_id uuid,
  p_participation_kind text,
  p_is_compatibility_primary boolean,
  p_basis jsonb,
  p_metadata jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_kind text := btrim(coalesce(p_participation_kind,''));
  v_existing atlas.ledger_organization_participations%rowtype;
  v_created atlas.ledger_organization_participations%rowtype;
begin
  if p_ledger_id is null or p_organization_id is null then
    raise exception 'Ledger and Organization are required.' using errcode='22023';
  end if;
  if v_kind='' then
    raise exception 'Participation kind required.' using errcode='22023';
  end if;
  if p_basis is null or jsonb_typeof(p_basis)<>'object' then
    raise exception 'Participation basis must be an object.' using errcode='22023';
  end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Participation metadata must be an object.' using errcode='22023';
  end if;
  if not exists (select 1 from atlas.ledgers l where l.id=p_ledger_id and l.status='active') then
    raise exception 'Active Ledger required.' using errcode='23503';
  end if;
  if not exists (select 1 from atlas.organizations o where o.id=p_organization_id and o.status='active') then
    raise exception 'Active Organization required.' using errcode='23503';
  end if;

  select p.* into v_existing
  from atlas.ledger_organization_participations p
  where p.ledger_id=p_ledger_id
    and p.organization_id=p_organization_id
    and p.participation_kind=v_kind
    and p.status='active'
  limit 1;

  if v_existing.id is not null then
    if v_existing.is_compatibility_primary is distinct from coalesce(p_is_compatibility_primary,false) then
      raise exception 'Organization / Ledger participation identity contradiction.' using errcode='23514';
    end if;
    return jsonb_build_object(
      'ok',true,
      'alreadyEstablished',true,
      'participationId',v_existing.id,
      'ledgerId',v_existing.ledger_id,
      'organizationId',v_existing.organization_id,
      'participationKind',v_existing.participation_kind,
      'isCompatibilityPrimary',v_existing.is_compatibility_primary
    );
  end if;

  if coalesce(p_is_compatibility_primary,false) and exists (
    select 1
    from atlas.ledger_organization_participations p
    where p.organization_id=p_organization_id
      and p.status='active'
      and p.is_compatibility_primary
  ) then
    raise exception 'Organization already has a different compatibility-primary Ledger.' using errcode='23505';
  end if;

  insert into atlas.ledger_organization_participations (
    ledger_id,organization_id,participation_kind,is_compatibility_primary,
    status,basis,metadata
  ) values (
    p_ledger_id,p_organization_id,v_kind,coalesce(p_is_compatibility_primary,false),
    'active',p_basis,p_metadata
  )
  returning * into v_created;

  return jsonb_build_object(
    'ok',true,
    'alreadyEstablished',false,
    'participationId',v_created.id,
    'ledgerId',v_created.ledger_id,
    'organizationId',v_created.organization_id,
    'participationKind',v_created.participation_kind,
    'isCompatibilityPrimary',v_created.is_compatibility_primary
  );
end;
$function$;

revoke all on function atlas.establish_ledger_organization_participation_v1(uuid,uuid,text,boolean,jsonb,jsonb)
  from public, anon, authenticated;
grant execute on function atlas.establish_ledger_organization_participation_v1(uuid,uuid,text,boolean,jsonb,jsonb)
  to service_role;

-- Existing organization-scoped projections now require active participation rather than
-- Ledger ownership. Explicit non-primary Ledger scope is valid when participation exists.
create or replace function atlas.organization_ledger_scope_compatibility_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_expected_ledger_id uuid;
begin
  if new.ledger_id is null then
    if new.organization_id is null then
      return new;
    end if;

    v_expected_ledger_id := atlas.primary_ledger_for_organization_v1(new.organization_id);
    if v_expected_ledger_id is null then
      raise exception 'Organization has no compatibility-primary Ledger.' using errcode='23514';
    end if;
    new.ledger_id := v_expected_ledger_id;
  end if;

  if new.organization_id is not null and not exists (
    select 1
    from atlas.ledger_organization_participations p
    join atlas.ledgers l on l.id=p.ledger_id and l.status='active'
    where p.organization_id=new.organization_id
      and p.ledger_id=new.ledger_id
      and p.status='active'
  ) then
    raise exception 'Organization does not actively participate in the selected Ledger.' using errcode='23514';
  end if;

  return new;
end;
$function$;

revoke all on function atlas.organization_ledger_scope_compatibility_v1()
  from public, anon, authenticated;

alter table atlas.organization_ledger_entries
  add constraint organization_ledger_entries_ledger_id_fkey
  foreign key (ledger_id) references atlas.ledgers(id) on delete restrict;

-- Entitlement is Ledger capability. Organization scope is now optional compatibility
-- context; when present it must be an active participant in the Ledger.
update atlas.ledger_entitlement_bindings b
set ledger_id = atlas.primary_ledger_for_organization_v1(b.organization_id)
where b.ledger_id is null
  and b.organization_id is not null;

alter table atlas.ledger_entitlement_bindings
  alter column organization_id drop not null,
  alter column ledger_id set not null;

alter table atlas.ledger_entitlement_bindings
  add constraint ledger_entitlement_bindings_unit_requires_org_check
  check (organization_unit_id is null or organization_id is not null);

drop index if exists atlas.ledger_entitlement_bindings_one_live_org_scope_uq;
create unique index ledger_entitlement_bindings_one_live_ledger_scope_uq
  on atlas.ledger_entitlement_bindings (ledger_id)
  where organization_unit_id is null and ended_at is null;

-- A Ledger may be born independently of an Organization and governed directly by a Principal.
create or replace function atlas.establish_ledger_for_principal_v1(
  p_principal_id uuid,
  p_person_id uuid,
  p_name text,
  p_ledger_kind text,
  p_basis text,
  p_metadata jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_principal atlas.principals%rowtype;
  v_name text := btrim(coalesce(p_name,''));
  v_kind text := btrim(coalesce(p_ledger_kind,''));
  v_basis text := btrim(coalesce(p_basis,''));
  v_stable_key text;
  v_ledger atlas.ledgers%rowtype;
  v_authority_id uuid;
begin
  if p_principal_id is null or p_person_id is null then
    raise exception 'Principal and Person are required.' using errcode='22023';
  end if;
  if length(v_name)<2 or length(v_name)>160 then
    raise exception 'Ledger name must be between 2 and 160 characters.' using errcode='22023';
  end if;
  if v_kind='' then
    raise exception 'Ledger kind required.' using errcode='22023';
  end if;
  if v_basis='' then
    raise exception 'Establishment basis required.' using errcode='22023';
  end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Ledger metadata must be an object.' using errcode='22023';
  end if;

  select p.* into v_principal
  from atlas.principals p
  where p.id=p_principal_id and p.status='active'
  for key share;

  if v_principal.id is null then
    raise exception 'Active Principal required.' using errcode='42501';
  end if;
  if v_principal.person_id is null or v_principal.person_id<>p_person_id then
    raise exception 'Principal / Person identity contradiction.' using errcode='23514';
  end if;

  loop
    v_stable_key := atlas.new_opaque_stable_key_v1();
    exit when not exists (select 1 from atlas.ledgers l where l.stable_key=v_stable_key);
  end loop;

  insert into atlas.ledgers (
    stable_key,name,organization_id,ledger_kind,status,metadata
  ) values (
    v_stable_key,v_name,null,v_kind,'active',
    p_metadata || jsonb_build_object(
      'establishment_basis',v_basis,
      'established_by_principal_id',p_principal_id,
      'established_by_person_id',p_person_id
    )
  ) returning * into v_ledger;

  insert into atlas.principal_ledger_authorities (
    principal_id,ledger_id,authority_kind,status,basis,metadata
  ) values (
    p_principal_id,v_ledger.id,'root_governing','active',v_basis,
    jsonb_build_object(
      'source','establish_ledger_for_principal_v1',
      'personId',p_person_id
    )
  ) returning id into v_authority_id;

  return jsonb_build_object(
    'ok',true,
    'ledger',jsonb_build_object(
      'id',v_ledger.id,
      'stable_key',v_ledger.stable_key,
      'name',v_ledger.name,
      'kind',v_ledger.ledger_kind,
      'status',v_ledger.status
    ),
    'authority',jsonb_build_object(
      'id',v_authority_id,
      'principal_id',p_principal_id,
      'kind','root_governing',
      'status','active',
      'basis',v_basis
    )
  );
end;
$function$;

revoke all on function atlas.establish_ledger_for_principal_v1(uuid,uuid,text,text,text,jsonb)
  from public, anon, authenticated;
grant execute on function atlas.establish_ledger_for_principal_v1(uuid,uuid,text,text,text,jsonb)
  to service_role;

-- Rewrite Organization establishment so the initial Ledger is a transactional workflow
-- choice represented through participation, not a universal one-to-one schema invariant.
create or replace function atlas.establish_organization_ledger_for_principal_v1(
  p_principal_id uuid,
  p_person_id uuid,
  p_human_user_id uuid,
  p_name text,
  p_create_owner_membership boolean,
  p_begin_onboarding boolean,
  p_establishment_basis text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_principal atlas.principals%rowtype;
  v_credential_person_id uuid;
  v_name text := btrim(coalesce(p_name,''));
  v_basis text := btrim(coalesce(p_establishment_basis,''));
  v_organization_id uuid := gen_random_uuid();
  v_stable_key text;
  v_ledger_result jsonb;
  v_ledger_id uuid;
  v_ledger_stable_key text;
  v_ledger_name text;
  v_ledger_kind text;
  v_ledger_status text;
  v_authority_id uuid;
  v_participation_result jsonb;
  v_membership_id uuid;
  v_reconstruction_session_id uuid;
  v_onboarding_state text;
begin
  if p_principal_id is null or p_person_id is null then
    raise exception 'Principal and Person are required.' using errcode='22023';
  end if;
  if length(v_name)<2 or length(v_name)>160 then
    raise exception 'Organization name must be between 2 and 160 characters.' using errcode='22023';
  end if;
  if v_basis='' then
    raise exception 'Establishment basis required.' using errcode='22023';
  end if;

  select p.* into v_principal
  from atlas.principals p
  where p.id=p_principal_id and p.status='active'
  for key share;

  if v_principal.id is null then
    raise exception 'Active Principal required.' using errcode='42501';
  end if;
  if v_principal.person_id is null or v_principal.person_id<>p_person_id then
    raise exception 'Principal / Person identity contradiction.' using errcode='23514';
  end if;

  if p_human_user_id is not null then
    if not exists (
      select 1 from auth.users u
      where u.id=p_human_user_id
        and u.deleted_at is null
        and (u.banned_until is null or u.banned_until<=now())
    ) then
      raise exception 'Authenticated human is unavailable.' using errcode='42501';
    end if;
    v_credential_person_id := atlas.ensure_person_for_auth_user_v1(p_human_user_id,null);
    if v_credential_person_id is null or v_credential_person_id<>p_person_id then
      raise exception 'Credential / Person identity contradiction.' using errcode='23514';
    end if;
  end if;

  if (p_create_owner_membership or p_begin_onboarding) and p_human_user_id is null then
    raise exception 'Credential evidence required for membership or onboarding.' using errcode='22023';
  end if;

  loop
    v_stable_key := atlas.new_opaque_stable_key_v1();
    exit when not exists (select 1 from atlas.organizations o where o.stable_key=v_stable_key);
  end loop;

  v_onboarding_state := case when p_begin_onboarding then 'connecting_sources' else 'new' end;

  insert into atlas.organizations (
    id,stable_key,name,status,metadata,onboarding_state,onboarding_started_at
  ) values (
    v_organization_id,v_stable_key,v_name,'active',
    jsonb_strip_nulls(jsonb_build_object(
      'establishment_mode','principal_institution_establishment',
      'established_by_principal_id',p_principal_id,
      'established_by_person_id',p_person_id,
      'establishment_basis',v_basis,
      'membership_claimed',p_create_owner_membership
    )),
    v_onboarding_state,
    case when p_begin_onboarding then now() else null end
  );

  v_ledger_result := atlas.establish_ledger_for_principal_v1(
    p_principal_id,p_person_id,v_name,'governed_reality',v_basis,
    jsonb_build_object(
      'source','establish_organization_ledger_for_principal_v1',
      'initialForOrganizationId',v_organization_id
    )
  );

  v_ledger_id := (v_ledger_result->'ledger'->>'id')::uuid;
  v_ledger_stable_key := v_ledger_result->'ledger'->>'stable_key';
  v_ledger_name := v_ledger_result->'ledger'->>'name';
  v_ledger_kind := v_ledger_result->'ledger'->>'kind';
  v_ledger_status := v_ledger_result->'ledger'->>'status';
  v_authority_id := (v_ledger_result->'authority'->>'id')::uuid;

  v_participation_result := atlas.establish_ledger_organization_participation_v1(
    v_ledger_id,v_organization_id,'governing',true,
    jsonb_build_object(
      'source','establish_organization_ledger_for_principal_v1',
      'establishmentBasis',v_basis
    ),
    jsonb_build_object('initialInstitutionalLedger',true)
  );

  if p_create_owner_membership then
    insert into atlas.organization_memberships (
      organization_id,user_id,person_id,role,active,permissions
    ) values (
      v_organization_id,p_human_user_id,p_person_id,'owner',true,'{}'::jsonb
    ) returning id into v_membership_id;
  end if;

  if p_begin_onboarding then
    insert into atlas.organization_onboarding_actors (
      organization_id,human_user_id,actor_kind,active,metadata
    ) values (
      v_organization_id,p_human_user_id,'setup_actor',true,
      jsonb_build_object(
        'source','establish_organization_ledger_for_principal_v1',
        'principalId',p_principal_id,
        'personId',p_person_id
      )
    );

    insert into atlas.reconstruction_sessions (
      human_user_id,target_organization_id,status,clean_room,
      allow_existing_atlas_canon,purpose,metadata
    ) values (
      p_human_user_id,v_organization_id,'collecting',true,false,
      'organization_onboarding',
      jsonb_build_object(
        'organization_stable_key',v_stable_key,
        'principalId',p_principal_id,
        'personId',p_person_id,
        'source','establish_organization_ledger_for_principal_v1'
      )
    ) returning id into v_reconstruction_session_id;
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'ok',true,
    'organization',jsonb_build_object(
      'id',v_organization_id,
      'stable_key',v_stable_key,
      'name',v_name,
      'status','active',
      'onboarding_state',v_onboarding_state
    ),
    'ledger',jsonb_build_object(
      'id',v_ledger_id,
      'stable_key',v_ledger_stable_key,
      'name',v_ledger_name,
      'kind',v_ledger_kind,
      'status',v_ledger_status
    ),
    'participation',v_participation_result,
    'authority',jsonb_build_object(
      'id',v_authority_id,
      'principal_id',p_principal_id,
      'kind','root_governing',
      'status','active',
      'basis',v_basis
    ),
    'membership',case when v_membership_id is null then null else jsonb_build_object(
      'id',v_membership_id,'role','owner','active',true,
      'person_id',p_person_id,'user_id',p_human_user_id
    ) end,
    'reconstruction',case when v_reconstruction_session_id is null then null else jsonb_build_object(
      'id',v_reconstruction_session_id,'clean_room',true,
      'allow_existing_atlas_canon',false,'target_organization_id',v_organization_id
    ) end,
    'membershipCreated',v_membership_id is not null,
    'onboardingBegun',p_begin_onboarding,
    'principalId',p_principal_id,
    'personId',p_person_id
  ));
end;
$function$;

revoke all on function atlas.establish_organization_ledger_for_principal_v1(uuid,uuid,uuid,text,boolean,boolean,text)
  from public, anon, authenticated;
grant execute on function atlas.establish_organization_ledger_for_principal_v1(uuid,uuid,uuid,text,boolean,boolean,text)
  to service_role;

-- Ledger graph edges. Cycles are intentionally not prohibited.
create table atlas.ledger_relationships (
  id uuid primary key default gen_random_uuid(),
  source_ledger_id uuid not null references atlas.ledgers(id) on delete restrict,
  target_ledger_id uuid not null references atlas.ledgers(id) on delete restrict,
  relationship_kind text not null check (btrim(relationship_kind)<>''),
  directionality text not null check (directionality in ('directed','symmetric')),
  status text not null default 'active' check (status in ('active','ended')),
  basis jsonb not null default '{}'::jsonb check (jsonb_typeof(basis)='object'),
  established_at timestamptz not null default now(),
  ended_at timestamptz,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (source_ledger_id<>target_ledger_id),
  check ((status='active' and ended_at is null) or (status='ended' and ended_at is not null))
);

create unique index ledger_relationships_active_identity_uq
  on atlas.ledger_relationships
  (source_ledger_id,target_ledger_id,relationship_kind,directionality)
  where status='active';

create index ledger_relationships_target_active_idx
  on atlas.ledger_relationships (target_ledger_id,source_ledger_id)
  where status='active';

alter table atlas.ledger_relationships enable row level security;
revoke all on atlas.ledger_relationships from anon, authenticated;

create trigger ledger_relationships_set_updated_at
before update on atlas.ledger_relationships
for each row execute function atlas.set_updated_at();

create or replace function atlas.establish_ledger_relationship_v1(
  p_source_ledger_id uuid,
  p_target_ledger_id uuid,
  p_relationship_kind text,
  p_directionality text,
  p_basis jsonb,
  p_metadata jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_source uuid := p_source_ledger_id;
  v_target uuid := p_target_ledger_id;
  v_kind text := btrim(coalesce(p_relationship_kind,''));
  v_direction text := btrim(coalesce(p_directionality,''));
  v_swap uuid;
  v_existing atlas.ledger_relationships%rowtype;
  v_created atlas.ledger_relationships%rowtype;
begin
  if v_source is null or v_target is null or v_source=v_target then
    raise exception 'Two distinct Ledgers are required.' using errcode='22023';
  end if;
  if v_kind='' then raise exception 'Relationship kind required.' using errcode='22023'; end if;
  if v_direction not in ('directed','symmetric') then
    raise exception 'Directionality must be directed or symmetric.' using errcode='22023';
  end if;
  if p_basis is null or jsonb_typeof(p_basis)<>'object' or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Relationship basis and metadata must be objects.' using errcode='22023';
  end if;
  if not exists (select 1 from atlas.ledgers l where l.id=v_source and l.status='active')
     or not exists (select 1 from atlas.ledgers l where l.id=v_target and l.status='active') then
    raise exception 'Both Ledgers must be active.' using errcode='23503';
  end if;

  if v_direction='symmetric' and v_source::text>v_target::text then
    v_swap:=v_source; v_source:=v_target; v_target:=v_swap;
  end if;

  select r.* into v_existing
  from atlas.ledger_relationships r
  where r.source_ledger_id=v_source
    and r.target_ledger_id=v_target
    and r.relationship_kind=v_kind
    and r.directionality=v_direction
    and r.status='active'
  limit 1;

  if v_existing.id is not null then
    return jsonb_build_object(
      'ok',true,'alreadyEstablished',true,'relationshipId',v_existing.id,
      'sourceLedgerId',v_existing.source_ledger_id,'targetLedgerId',v_existing.target_ledger_id,
      'relationshipKind',v_existing.relationship_kind,'directionality',v_existing.directionality
    );
  end if;

  insert into atlas.ledger_relationships (
    source_ledger_id,target_ledger_id,relationship_kind,directionality,status,basis,metadata
  ) values (
    v_source,v_target,v_kind,v_direction,'active',p_basis,p_metadata
  ) returning * into v_created;

  return jsonb_build_object(
    'ok',true,'alreadyEstablished',false,'relationshipId',v_created.id,
    'sourceLedgerId',v_created.source_ledger_id,'targetLedgerId',v_created.target_ledger_id,
    'relationshipKind',v_created.relationship_kind,'directionality',v_created.directionality
  );
end;
$function$;

revoke all on function atlas.establish_ledger_relationship_v1(uuid,uuid,text,text,jsonb,jsonb)
  from public, anon, authenticated;
grant execute on function atlas.establish_ledger_relationship_v1(uuid,uuid,text,text,jsonb,jsonb)
  to service_role;

-- Specific governed reality can correlate across Ledgers without merging either side.
create table atlas.ledger_correlations (
  id uuid primary key default gen_random_uuid(),
  correlation_key uuid not null unique,
  source_ledger_id uuid not null references atlas.ledgers(id) on delete restrict,
  source_subject_kind text not null check (btrim(source_subject_kind)<>''),
  source_subject_id uuid,
  source_subject_key text,
  source_path text,
  target_ledger_id uuid not null references atlas.ledgers(id) on delete restrict,
  target_subject_kind text not null check (btrim(target_subject_kind)<>''),
  target_subject_id uuid,
  target_subject_key text,
  target_path text,
  correlation_kind text not null check (btrim(correlation_kind)<>''),
  directionality text not null check (directionality in ('directed','symmetric')),
  status text not null default 'active' check (status in ('active','ended')),
  basis jsonb not null default '{}'::jsonb check (jsonb_typeof(basis)='object'),
  established_at timestamptz not null default now(),
  ended_at timestamptz,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (source_ledger_id<>target_ledger_id),
  check (source_subject_id is not null or nullif(btrim(source_subject_key),'') is not null),
  check (target_subject_id is not null or nullif(btrim(target_subject_key),'') is not null),
  check ((status='active' and ended_at is null) or (status='ended' and ended_at is not null))
);

create unique index ledger_correlations_active_semantic_uq
  on atlas.ledger_correlations (
    source_ledger_id,
    source_subject_kind,
    coalesce(source_subject_id,'00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(source_subject_key,''),
    coalesce(source_path,''),
    target_ledger_id,
    target_subject_kind,
    coalesce(target_subject_id,'00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(target_subject_key,''),
    coalesce(target_path,''),
    correlation_kind,
    directionality
  ) where status='active';

alter table atlas.ledger_correlations enable row level security;
revoke all on atlas.ledger_correlations from anon, authenticated;

create trigger ledger_correlations_set_updated_at
before update on atlas.ledger_correlations
for each row execute function atlas.set_updated_at();

create or replace function atlas.establish_ledger_correlation_v1(
  p_correlation_key uuid,
  p_source_ledger_id uuid,
  p_source_subject_kind text,
  p_source_subject_id uuid,
  p_source_subject_key text,
  p_source_path text,
  p_target_ledger_id uuid,
  p_target_subject_kind text,
  p_target_subject_id uuid,
  p_target_subject_key text,
  p_target_path text,
  p_correlation_kind text,
  p_directionality text,
  p_basis jsonb,
  p_metadata jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_sl uuid := p_source_ledger_id;
  v_sk text := btrim(coalesce(p_source_subject_kind,''));
  v_si uuid := p_source_subject_id;
  v_ssk text := nullif(btrim(coalesce(p_source_subject_key,'')),'');
  v_sp text := nullif(btrim(coalesce(p_source_path,'')),'');
  v_tl uuid := p_target_ledger_id;
  v_tk text := btrim(coalesce(p_target_subject_kind,''));
  v_ti uuid := p_target_subject_id;
  v_tsk text := nullif(btrim(coalesce(p_target_subject_key,'')),'');
  v_tp text := nullif(btrim(coalesce(p_target_path,'')),'');
  v_kind text := btrim(coalesce(p_correlation_kind,''));
  v_direction text := btrim(coalesce(p_directionality,''));
  v_source_sort text;
  v_target_sort text;
  x_l uuid; x_k text; x_i uuid; x_sk text; x_p text;
  v_existing atlas.ledger_correlations%rowtype;
  v_created atlas.ledger_correlations%rowtype;
begin
  if p_correlation_key is null then raise exception 'Correlation key required.' using errcode='22023'; end if;
  if v_sl is null or v_tl is null or v_sl=v_tl then raise exception 'Two distinct Ledgers are required.' using errcode='22023'; end if;
  if v_sk='' or v_tk='' or v_kind='' then raise exception 'Subject and correlation kinds are required.' using errcode='22023'; end if;
  if v_si is null and v_ssk is null then raise exception 'Source subject address required.' using errcode='22023'; end if;
  if v_ti is null and v_tsk is null then raise exception 'Target subject address required.' using errcode='22023'; end if;
  if v_direction not in ('directed','symmetric') then raise exception 'Directionality must be directed or symmetric.' using errcode='22023'; end if;
  if p_basis is null or jsonb_typeof(p_basis)<>'object' or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Correlation basis and metadata must be objects.' using errcode='22023';
  end if;
  if not exists (select 1 from atlas.ledgers l where l.id=v_sl and l.status='active')
     or not exists (select 1 from atlas.ledgers l where l.id=v_tl and l.status='active') then
    raise exception 'Both Ledgers must be active.' using errcode='23503';
  end if;

  v_source_sort := v_sl::text||'|'||v_sk||'|'||coalesce(v_si::text,'')||'|'||coalesce(v_ssk,'')||'|'||coalesce(v_sp,'');
  v_target_sort := v_tl::text||'|'||v_tk||'|'||coalesce(v_ti::text,'')||'|'||coalesce(v_tsk,'')||'|'||coalesce(v_tp,'');
  if v_direction='symmetric' and v_source_sort>v_target_sort then
    x_l:=v_sl; x_k:=v_sk; x_i:=v_si; x_sk:=v_ssk; x_p:=v_sp;
    v_sl:=v_tl; v_sk:=v_tk; v_si:=v_ti; v_ssk:=v_tsk; v_sp:=v_tp;
    v_tl:=x_l; v_tk:=x_k; v_ti:=x_i; v_tsk:=x_sk; v_tp:=x_p;
  end if;

  select c.* into v_existing
  from atlas.ledger_correlations c
  where c.correlation_key=p_correlation_key;

  if v_existing.id is not null then
    if v_existing.source_ledger_id is distinct from v_sl
       or v_existing.source_subject_kind is distinct from v_sk
       or v_existing.source_subject_id is distinct from v_si
       or v_existing.source_subject_key is distinct from v_ssk
       or v_existing.source_path is distinct from v_sp
       or v_existing.target_ledger_id is distinct from v_tl
       or v_existing.target_subject_kind is distinct from v_tk
       or v_existing.target_subject_id is distinct from v_ti
       or v_existing.target_subject_key is distinct from v_tsk
       or v_existing.target_path is distinct from v_tp
       or v_existing.correlation_kind is distinct from v_kind
       or v_existing.directionality is distinct from v_direction then
      raise exception 'Correlation identity contradiction.' using errcode='23514';
    end if;

    return jsonb_build_object(
      'ok',true,'alreadyEstablished',true,'correlationId',v_existing.id,
      'correlationKey',v_existing.correlation_key,
      'sourceLedgerId',v_existing.source_ledger_id,'targetLedgerId',v_existing.target_ledger_id,
      'correlationKind',v_existing.correlation_kind,'directionality',v_existing.directionality
    );
  end if;

  insert into atlas.ledger_correlations (
    correlation_key,
    source_ledger_id,source_subject_kind,source_subject_id,source_subject_key,source_path,
    target_ledger_id,target_subject_kind,target_subject_id,target_subject_key,target_path,
    correlation_kind,directionality,status,basis,metadata
  ) values (
    p_correlation_key,
    v_sl,v_sk,v_si,v_ssk,v_sp,
    v_tl,v_tk,v_ti,v_tsk,v_tp,
    v_kind,v_direction,'active',p_basis,p_metadata
  ) returning * into v_created;

  return jsonb_build_object(
    'ok',true,'alreadyEstablished',false,'correlationId',v_created.id,
    'correlationKey',v_created.correlation_key,
    'sourceLedgerId',v_created.source_ledger_id,'targetLedgerId',v_created.target_ledger_id,
    'correlationKind',v_created.correlation_kind,'directionality',v_created.directionality
  );
end;
$function$;

revoke all on function atlas.establish_ledger_correlation_v1(uuid,uuid,text,uuid,text,text,uuid,text,uuid,text,text,text,text,jsonb,jsonb)
  from public, anon, authenticated;
grant execute on function atlas.establish_ledger_correlation_v1(uuid,uuid,text,uuid,text,text,uuid,text,uuid,text,text,text,text,jsonb,jsonb)
  to service_role;

-- Commercial implementation binds capability to an existing governed Ledger. Organization
-- is optional compatibility context; if supplied it must actively participate in the Ledger.
create or replace function atlas.bind_implementation_ledger_entitlement_self_api_v1(
  p_implementation_case_id uuid,
  p_institution_item_id uuid,
  p_ledger_scope_item_id uuid,
  p_ledger_entitlement_id uuid,
  p_organization_id uuid,
  p_ledger_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_practitioner_participant_id uuid;
  v_setup_sponsor_participant_id uuid;
  v_setup_sponsor_user_id uuid;
  v_sponsor_person_id uuid;
  v_sponsor_principal_id uuid;
  v_entitlement atlas.ledger_entitlements%rowtype;
  v_binding atlas.ledger_entitlement_bindings%rowtype;
  v_organization atlas.organizations%rowtype;
  v_ledger atlas.ledgers%rowtype;
  v_starting_label text;
begin
  if v_uid is null or not atlas.implementation_practitioner_authorized_self_v1() then
    raise exception 'Practitioner authority required.' using errcode='42501';
  end if;

  select cp.id into v_practitioner_participant_id
  from atlas.implementation_case_participants cp
  where cp.implementation_case_id=p_implementation_case_id
    and cp.relationship_kind='practitioner'
    and cp.active and cp.human_user_id=v_uid
  limit 1;
  if v_practitioner_participant_id is null then
    raise exception 'This implementation case is not assigned to the current practitioner.' using errcode='42501';
  end if;

  select cp.id,cp.human_user_id into v_setup_sponsor_participant_id,v_setup_sponsor_user_id
  from atlas.implementation_case_participants cp
  where cp.implementation_case_id=p_implementation_case_id
    and cp.relationship_kind='setup_sponsor'
    and cp.active and cp.verified_at is not null
  limit 1;
  if v_setup_sponsor_participant_id is null then
    raise exception 'A verified setup sponsor is required before commercial Ledger binding.' using errcode='23514';
  end if;

  select c.person_id into v_sponsor_person_id
  from atlas.person_auth_credentials c
  join atlas.people p on p.id=c.person_id
  where c.auth_user_id=v_setup_sponsor_user_id
    and c.status='active' and p.status='active'
  limit 1;
  if v_sponsor_person_id is null then
    raise exception 'Verified setup sponsor must resolve to a Canonical Person.' using errcode='23514';
  end if;

  select p.id into v_sponsor_principal_id
  from atlas.principals p
  where p.person_id=v_sponsor_person_id and p.status='active'
  order by p.created_at limit 1;
  if v_sponsor_principal_id is null then
    raise exception 'Verified setup sponsor must have an active Principal.' using errcode='23514';
  end if;

  if p_organization_id is not null then
    select o.* into v_organization
    from atlas.organizations o
    where o.id=p_organization_id and o.status='active';
    if v_organization.id is null then
      raise exception 'Active target Organization required.' using errcode='23503';
    end if;
  end if;

  select l.* into v_ledger
  from atlas.ledgers l
  where l.id=p_ledger_id and l.status='active';
  if v_ledger.id is null then
    raise exception 'Active target Ledger required.' using errcode='23503';
  end if;

  if p_organization_id is not null and not exists (
    select 1 from atlas.ledger_organization_participations p
    where p.ledger_id=p_ledger_id
      and p.organization_id=p_organization_id
      and p.status='active'
  ) then
    raise exception 'Target Organization does not actively participate in the target Ledger.' using errcode='23514';
  end if;

  if not atlas.principal_has_ledger_authority_v1(v_sponsor_principal_id,p_ledger_id) then
    raise exception 'Verified setup sponsor Principal does not govern the target Ledger.' using errcode='42501';
  end if;

  if not exists (
    select 1 from atlas.implementation_establishment_items e
    where e.id=p_institution_item_id and e.implementation_case_id=p_implementation_case_id
      and e.category='institution' and e.status='established'
  ) then
    raise exception 'An established Institution record is required.' using errcode='23514';
  end if;

  if not exists (
    select 1 from atlas.implementation_establishment_items e
    where e.id=p_ledger_scope_item_id and e.implementation_case_id=p_implementation_case_id
      and e.category='ledger_scope' and e.status='established'
  ) then
    raise exception 'An established Ledger scope record is required.' using errcode='23514';
  end if;

  select le.* into v_entitlement
  from atlas.ledger_entitlements le
  where le.id=p_ledger_entitlement_id and le.implementation_case_id=p_implementation_case_id
  for update;
  if v_entitlement.id is null then
    raise exception 'Ledger entitlement not found for this implementation case.' using errcode='23503';
  end if;

  select b.* into v_binding
  from atlas.ledger_entitlement_bindings b
  where b.ledger_entitlement_id=v_entitlement.id and b.ended_at is null
  limit 1;

  if v_binding.id is not null then
    if v_binding.organization_id is not distinct from p_organization_id
       and v_binding.ledger_id=p_ledger_id then
      return jsonb_build_object(
        'ok',true,'alreadyBound',true,
        'implementationCaseId',p_implementation_case_id,
        'organizationId',p_organization_id,
        'organizationName',v_organization.name,
        'ledgerId',p_ledger_id,
        'ledgerStableKey',v_ledger.stable_key,
        'ledgerName',v_ledger.name,
        'ledgerEntitlementId',v_entitlement.id,
        'bindingId',v_binding.id,'bindingState',v_binding.state,
        'setupSponsorParticipantId',v_setup_sponsor_participant_id,
        'setupSponsorPrincipalId',v_sponsor_principal_id,
        'organizationCreated',false,'principalCreated',false,'membershipCreated',false
      );
    end if;
    raise exception 'Ledger entitlement is already bound to a different institutional scope.' using errcode='23505';
  end if;

  if v_entitlement.state not in ('available','reserved') then
    raise exception 'Ledger entitlement is not available for initial binding.' using errcode='23514';
  end if;

  if exists (
    select 1 from atlas.ledger_entitlement_bindings b
    where b.ledger_id=p_ledger_id
      and b.organization_unit_id is null
      and b.ended_at is null
      and b.ledger_entitlement_id<>v_entitlement.id
  ) then
    raise exception 'Target Ledger already has a live root-scope entitlement binding.' using errcode='23505';
  end if;

  select p.starting_label into v_starting_label
  from atlas.implementation_cases c
  join atlas.implementation_purchases p on p.id=c.implementation_purchase_id
  where c.id=p_implementation_case_id;
  if v_starting_label is null then
    raise exception 'Implementation purchase is unavailable.' using errcode='23503';
  end if;

  insert into atlas.ledger_entitlement_bindings (
    implementation_case_id,ledger_entitlement_id,organization_id,organization_unit_id,
    bound_by_participant_id,state,binding_basis,metadata,ledger_id
  ) values (
    p_implementation_case_id,v_entitlement.id,p_organization_id,null,
    v_practitioner_participant_id,'bound',
    jsonb_strip_nulls(jsonb_build_object(
      'source','bind_implementation_ledger_entitlement_self_api_v1',
      'institutionEstablishmentItemId',p_institution_item_id,
      'ledgerScopeEstablishmentItemId',p_ledger_scope_item_id,
      'practitionerParticipantId',v_practitioner_participant_id,
      'setupSponsorParticipantId',v_setup_sponsor_participant_id,
      'setupSponsorPrincipalId',v_sponsor_principal_id,
      'targetLedgerId',p_ledger_id,
      'targetOrganizationId',p_organization_id
    )),
    jsonb_build_object('purchaseStartingLabel',v_starting_label,'institutionalRealityPreexisting',true),
    p_ledger_id
  ) returning * into v_binding;

  update atlas.ledger_entitlements set state='bound',updated_at=now()
  where id=v_entitlement.id;

  update atlas.implementation_cases
  set metadata=metadata||jsonb_strip_nulls(jsonb_build_object(
      'commercialLedgerBindingEstablishedAt',now(),
      'organizationId',p_organization_id,
      'ledgerId',p_ledger_id,
      'baselineLedgerBindingId',v_binding.id,
      'setupSponsorPrincipalId',v_sponsor_principal_id
    )),updated_at=now()
  where id=p_implementation_case_id;

  return jsonb_build_object(
    'ok',true,'alreadyBound',false,
    'implementationCaseId',p_implementation_case_id,
    'organizationId',p_organization_id,
    'organizationName',v_organization.name,
    'ledgerId',p_ledger_id,
    'ledgerStableKey',v_ledger.stable_key,
    'ledgerName',v_ledger.name,
    'ledgerEntitlementId',v_entitlement.id,
    'bindingId',v_binding.id,'bindingState',v_binding.state,
    'setupSponsorParticipantId',v_setup_sponsor_participant_id,
    'setupSponsorPrincipalId',v_sponsor_principal_id,
    'organizationCreated',false,'principalCreated',false,'membershipCreated',false
  );
end;
$function$;

revoke all on function atlas.bind_implementation_ledger_entitlement_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid)
  from public, anon;
grant execute on function atlas.bind_implementation_ledger_entitlement_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid)
  to authenticated;

-- Principal Ledger projection no longer assumes each Ledger has exactly one Organization.
-- Compatibility-primary Organization fields remain for old callers; organizations[] exposes
-- the graph participation set.
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
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  v_principal_id := atlas.current_principal_id_v1();
  if v_principal_id is null then
    return jsonb_build_object(
      'contractVersion','principal_ledgers_self_v1',
      'state','principal_required','items','[]'::jsonb
    );
  end if;

  select coalesce(jsonb_agg(x.item order by x.sort_name,x.ledger_id),'[]'::jsonb)
  into v_items
  from (
    select
      l.id as ledger_id,
      coalesce(po.organization_name,l.name) as sort_name,
      jsonb_build_object(
        'ledgerId',l.id,
        'ledgerStableKey',l.stable_key,
        'ledgerName',l.name,
        'ledgerKind',l.ledger_kind,
        'ledgerStatus',l.status,
        'organizationId',po.organization_id,
        'organizationStableKey',po.organization_stable_key,
        'organizationName',po.organization_name,
        'organizations',coalesce(orgs.items,'[]'::jsonb),
        'authorityKind',a.authority_kind,
        'scopeState',coalesce(l.metadata->>'scope_state','canonical')
      ) as item
    from atlas.principal_ledger_authorities a
    join atlas.ledgers l on l.id=a.ledger_id and l.status='active'
    left join lateral (
      select o.id as organization_id,o.stable_key as organization_stable_key,o.name as organization_name
      from atlas.ledger_organization_participations p
      join atlas.organizations o on o.id=p.organization_id and o.status='active'
      where p.ledger_id=l.id and p.status='active' and p.is_compatibility_primary
      limit 1
    ) po on true
    left join lateral (
      select jsonb_agg(jsonb_build_object(
        'organizationId',o.id,
        'organizationStableKey',o.stable_key,
        'organizationName',o.name,
        'participationKind',p.participation_kind,
        'isCompatibilityPrimary',p.is_compatibility_primary
      ) order by o.name,p.participation_kind) as items
      from atlas.ledger_organization_participations p
      join atlas.organizations o on o.id=p.organization_id
      where p.ledger_id=l.id and p.status='active'
    ) orgs on true
    where a.principal_id=v_principal_id
      and a.status='active'
      and a.authority_kind='root_governing'
  ) x;

  return jsonb_build_object(
    'contractVersion','principal_ledgers_self_v1',
    'state','ready','principalId',v_principal_id,'items',v_items
  );
end;
$function$;

revoke all on function atlas.principal_ledgers_self_api_v1()
  from public, anon;
grant execute on function atlas.principal_ledgers_self_api_v1()
  to authenticated;

COMMIT;
