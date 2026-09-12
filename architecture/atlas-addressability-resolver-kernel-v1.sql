-- Atlas Addressability + Resolver Kernel v1
-- PRE-MIGRATION EXECUTABLE CANDIDATE ONLY.
-- Canonical migration filename/version must be generated through the pinned
-- Supabase CLI workflow before this SQL may enter supabase/migrations.
--
-- Scope:
--   * durable network-level Addressable Subject
--   * bounded Atlas institution publication authority
--   * Addressable Interface registration
--   * exact authenticated resolution
--   * institutional contact resolver
--   * source-attributed external route resolver
--   * Local -> Addressable Subject reconciliation assertions
--
-- Explicitly not included:
--   * anonymous/public-web resolution
--   * public Person/Household enumeration
--   * semantic Building/Place kernel
--   * event or wholesale-availability public projections
--   * arbitrary resolver SQL/JSON execution

BEGIN;

create table atlas.addressable_subjects (
  id uuid primary key default gen_random_uuid(),
  subject_kind text not null check (subject_kind in ('organization','institution')),
  lifecycle_state text not null default 'active' check (lifecycle_state in ('active','retired')),
  creation_authority text not null check (creation_authority in ('externally_observed','atlas_institution')),
  created_by_user_id uuid null references auth.users(id) on delete set null,
  creation_basis jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  retired_at timestamptz null,
  check (jsonb_typeof(creation_basis) = 'object'),
  check (retired_at is null or lifecycle_state='retired')
);

comment on table atlas.addressable_subjects is
  'Thin network-level Atlas identity anchor for entities that may participate in governed resolution. It does not own names, routes, providers, locations, Local state, or organizational operating truth.';

create index addressable_subjects_kind_state_idx
  on atlas.addressable_subjects(subject_kind,lifecycle_state,created_at);

create table atlas.addressable_subject_institution_bindings (
  id uuid primary key default gen_random_uuid(),
  addressable_subject_id uuid not null references atlas.addressable_subjects(id) on delete restrict,
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  organization_unit_id uuid null references atlas.organization_units(id) on delete restrict,
  binding_state text not null default 'active' check (binding_state in ('active','revoked','superseded')),
  publication_authority text not null default 'entity_authorized' check (publication_authority in ('entity_authorized')),
  basis jsonb not null default '{}'::jsonb,
  established_by_user_id uuid null references auth.users(id) on delete set null,
  established_at timestamptz not null default now(),
  ended_at timestamptz null,
  check (jsonb_typeof(basis)='object'),
  check (ended_at is null or binding_state in ('revoked','superseded'))
);

create unique index addressable_subject_active_institution_binding_uidx
  on atlas.addressable_subject_institution_bindings(addressable_subject_id)
  where binding_state='active';

create index addressable_subject_binding_org_unit_idx
  on atlas.addressable_subject_institution_bindings(organization_id,organization_unit_id,binding_state);

comment on table atlas.addressable_subject_institution_bindings is
  'Explicit Atlas institutional publication authority for an Addressable Subject. Binding does not merge tenant Identity Subjects or Local entities and does not imply provider transport ownership.';

create table atlas.addressable_interfaces (
  id uuid primary key default gen_random_uuid(),
  addressable_subject_id uuid not null references atlas.addressable_subjects(id) on delete restrict,
  stable_key text not null,
  display_name text null,
  interface_state text not null default 'active' check (interface_state in ('active','inactive','retired')),
  visibility_scope text not null default 'authenticated_exact' check (visibility_scope in ('authenticated_exact','authenticated_discovery')),
  resolver_kind text not null check (resolver_kind in ('institutional_communication_endpoint','source_attributed_external_route')),
  resolver_config jsonb not null default '{}'::jsonb,
  publication_basis jsonb not null default '{}'::jsonb,
  established_by_user_id uuid null references auth.users(id) on delete set null,
  established_at timestamptz not null default now(),
  retired_at timestamptz null,
  check (stable_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  check (display_name is null or btrim(display_name)<>''),
  check (jsonb_typeof(resolver_config)='object'),
  check (jsonb_typeof(publication_basis)='object'),
  check (retired_at is null or interface_state='retired'),
  unique(addressable_subject_id,stable_key)
);

comment on table atlas.addressable_interfaces is
  'Governed subject-specific interfaces. Rows expose only interface identity/policy and bounded resolver kind; target-domain current truth remains in its owning domain.';

create index addressable_interfaces_subject_state_idx
  on atlas.addressable_interfaces(addressable_subject_id,interface_state,visibility_scope);

create table atlas.addressable_subject_local_assertions (
  id uuid primary key default gen_random_uuid(),
  local_context_id uuid not null references local_intel.local_contexts(id) on delete restrict,
  local_entity_id uuid not null references local_intel.entities(id) on delete restrict,
  addressable_subject_id uuid not null references atlas.addressable_subjects(id) on delete restrict,
  assertion_kind text not null check (assertion_kind in ('supports','probable','non_match')),
  confidence numeric null check (confidence is null or (confidence>=0 and confidence<=1)),
  basis jsonb not null default '{}'::jsonb,
  adjudication_state text not null default 'unresolved' check (adjudication_state in ('unresolved','accepted','rejected','superseded')),
  adjudicated_by_user_id uuid null references auth.users(id) on delete set null,
  adjudicated_at timestamptz null,
  created_at timestamptz not null default now(),
  check (jsonb_typeof(basis)='object')
);

create index addressable_subject_local_assertions_entity_idx
  on atlas.addressable_subject_local_assertions(local_context_id,local_entity_id,created_at desc);
create index addressable_subject_local_assertions_subject_idx
  on atlas.addressable_subject_local_assertions(addressable_subject_id,created_at desc);

comment on table atlas.addressable_subject_local_assertions is
  'Local-side evidence that a Local-owned entity may correspond to a network Addressable Subject. Private Local relevance/research state remains Local-owned.';

-- ---------------------------------------------------------------------------
-- Integrity guards
-- ---------------------------------------------------------------------------

create or replace function atlas.guard_addressable_subject_institution_binding_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, atlas
as $function$
begin
  if new.organization_unit_id is not null and not exists (
    select 1
    from atlas.organization_units u
    where u.id=new.organization_unit_id
      and u.organization_id=new.organization_id
  ) then
    raise exception 'Addressable Subject institution binding organization unit is outside organization.' using errcode='23514';
  end if;
  return new;
end;
$function$;

create trigger addressable_subject_institution_binding_guard
before insert or update on atlas.addressable_subject_institution_bindings
for each row execute function atlas.guard_addressable_subject_institution_binding_v1();

create or replace function atlas.guard_addressable_local_assertion_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, atlas, local_intel
as $function$
begin
  if not exists (
    select 1
    from local_intel.entities e
    where e.id=new.local_entity_id
      and e.local_context_id=new.local_context_id
  ) then
    raise exception 'Local entity is outside Local context.' using errcode='23514';
  end if;
  return new;
end;
$function$;

create trigger addressable_subject_local_assertion_guard
before insert or update on atlas.addressable_subject_local_assertions
for each row execute function atlas.guard_addressable_local_assertion_v1();

-- ---------------------------------------------------------------------------
-- Internal service establishment seams
-- ---------------------------------------------------------------------------

create or replace function atlas.establish_addressable_subject_for_institution_service_v1(
  p_organization_id uuid,
  p_organization_unit_id uuid,
  p_subject_kind text,
  p_creation_basis jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_subject atlas.addressable_subjects%rowtype;
  v_binding atlas.addressable_subject_institution_bindings%rowtype;
begin
  if current_user not in ('postgres','service_role') then
    raise exception 'Service authority required.' using errcode='42501';
  end if;

  if p_subject_kind not in ('organization','institution') then
    raise exception 'Unsupported addressable subject kind.' using errcode='22023';
  end if;

  if not exists(select 1 from atlas.organizations o where o.id=p_organization_id and o.status='active') then
    raise exception 'Active organization required.' using errcode='23503';
  end if;

  if p_organization_unit_id is not null and not exists(
    select 1 from atlas.organization_units u
    where u.id=p_organization_unit_id and u.organization_id=p_organization_id and u.status='active'
  ) then
    raise exception 'Active organization unit required.' using errcode='23503';
  end if;

  select s.* into v_subject
  from atlas.addressable_subject_institution_bindings b
  join atlas.addressable_subjects s on s.id=b.addressable_subject_id
  where b.organization_id=p_organization_id
    and b.organization_unit_id is not distinct from p_organization_unit_id
    and b.binding_state='active'
    and s.lifecycle_state='active'
  order by b.established_at
  limit 2;

  if v_subject.id is not null then
    return jsonb_build_object(
      'contractVersion','addressable_subject_v1',
      'addressableSubjectId',v_subject.id,
      'state','existing'
    );
  end if;

  insert into atlas.addressable_subjects(subject_kind,creation_authority,creation_basis)
  values(p_subject_kind,'atlas_institution',coalesce(p_creation_basis,'{}'::jsonb))
  returning * into v_subject;

  insert into atlas.addressable_subject_institution_bindings(
    addressable_subject_id,organization_id,organization_unit_id,basis
  ) values (
    v_subject.id,p_organization_id,p_organization_unit_id,coalesce(p_creation_basis,'{}'::jsonb)
  ) returning * into v_binding;

  return jsonb_build_object(
    'contractVersion','addressable_subject_v1',
    'addressableSubjectId',v_subject.id,
    'bindingId',v_binding.id,
    'state','established'
  );
end;
$function$;

create or replace function atlas.establish_external_addressable_subject_service_v1(
  p_subject_kind text,
  p_creation_basis jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare v_subject atlas.addressable_subjects%rowtype;
begin
  if current_user not in ('postgres','service_role') then
    raise exception 'Service authority required.' using errcode='42501';
  end if;
  if p_subject_kind not in ('organization','institution') then
    raise exception 'Unsupported addressable subject kind.' using errcode='22023';
  end if;
  insert into atlas.addressable_subjects(subject_kind,creation_authority,creation_basis)
  values(p_subject_kind,'externally_observed',coalesce(p_creation_basis,'{}'::jsonb))
  returning * into v_subject;
  return jsonb_build_object('contractVersion','addressable_subject_v1','addressableSubjectId',v_subject.id,'state','established');
end;
$function$;

create or replace function atlas.publish_addressable_interface_service_v1(
  p_addressable_subject_id uuid,
  p_stable_key text,
  p_display_name text,
  p_visibility_scope text,
  p_resolver_kind text,
  p_resolver_config jsonb default '{}'::jsonb,
  p_publication_basis jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare v_interface atlas.addressable_interfaces%rowtype;
begin
  if current_user not in ('postgres','service_role') then
    raise exception 'Service authority required.' using errcode='42501';
  end if;
  if not exists(select 1 from atlas.addressable_subjects s where s.id=p_addressable_subject_id and s.lifecycle_state='active') then
    raise exception 'Active Addressable Subject required.' using errcode='23503';
  end if;
  if p_visibility_scope not in ('authenticated_exact','authenticated_discovery') then
    raise exception 'Unsupported visibility scope.' using errcode='22023';
  end if;
  if p_resolver_kind not in ('institutional_communication_endpoint','source_attributed_external_route') then
    raise exception 'Unsupported resolver kind.' using errcode='22023';
  end if;

  insert into atlas.addressable_interfaces(
    addressable_subject_id,stable_key,display_name,visibility_scope,resolver_kind,resolver_config,publication_basis
  ) values (
    p_addressable_subject_id,btrim(p_stable_key),nullif(btrim(p_display_name),''),p_visibility_scope,p_resolver_kind,
    coalesce(p_resolver_config,'{}'::jsonb),coalesce(p_publication_basis,'{}'::jsonb)
  )
  on conflict(addressable_subject_id,stable_key)
  do update set
    display_name=excluded.display_name,
    interface_state='active',
    visibility_scope=excluded.visibility_scope,
    resolver_kind=excluded.resolver_kind,
    resolver_config=excluded.resolver_config,
    publication_basis=excluded.publication_basis,
    retired_at=null
  returning * into v_interface;

  return jsonb_build_object(
    'contractVersion','addressable_interface_v1',
    'addressableInterfaceId',v_interface.id,
    'addressableSubjectId',v_interface.addressable_subject_id,
    'stableKey',v_interface.stable_key,
    'resolverKind',v_interface.resolver_kind,
    'state',v_interface.interface_state
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- Authenticated read membrane
-- ---------------------------------------------------------------------------

create or replace function atlas.resolve_addressable_subject_exact_self_api_v1(
  p_addressable_subject_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_subject atlas.addressable_subjects%rowtype;
  v_binding atlas.addressable_subject_institution_bindings%rowtype;
  v_interfaces jsonb;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select * into v_subject
  from atlas.addressable_subjects
  where id=p_addressable_subject_id and lifecycle_state='active';

  if v_subject.id is null then
    return jsonb_build_object('contractVersion','addressable_resolution_v1','state','not_found');
  end if;

  select * into v_binding
  from atlas.addressable_subject_institution_bindings
  where addressable_subject_id=v_subject.id and binding_state='active'
  order by established_at desc
  limit 1;

  select coalesce(jsonb_agg(jsonb_build_object(
      'stableKey',i.stable_key,
      'displayName',i.display_name,
      'resolverKind',i.resolver_kind
    ) order by i.stable_key),'[]'::jsonb)
  into v_interfaces
  from atlas.addressable_interfaces i
  where i.addressable_subject_id=v_subject.id
    and i.interface_state='active'
    and i.visibility_scope in ('authenticated_exact','authenticated_discovery');

  return jsonb_build_object(
    'contractVersion','addressable_resolution_v1',
    'state','resolved',
    'addressableSubjectId',v_subject.id,
    'subjectKind',v_subject.subject_kind,
    'authorityPosition',case when v_binding.id is null then 'externally_observed' else 'entity_authorized' end,
    'organizationId',v_binding.organization_id,
    'organizationUnitId',v_binding.organization_unit_id,
    'interfaces',v_interfaces
  );
end;
$function$;

create or replace function atlas.resolve_addressable_interface_self_api_v1(
  p_addressable_subject_id uuid,
  p_interface_key text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_interface atlas.addressable_interfaces%rowtype;
  v_binding atlas.addressable_subject_institution_bindings%rowtype;
  v_endpoint atlas.communication_endpoints%rowtype;
  v_routes jsonb;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select * into v_interface
  from atlas.addressable_interfaces
  where addressable_subject_id=p_addressable_subject_id
    and stable_key=btrim(p_interface_key)
    and interface_state='active'
    and visibility_scope in ('authenticated_exact','authenticated_discovery');

  if v_interface.id is null then
    return jsonb_build_object('contractVersion','addressable_interface_resolution_v1','state','interface_not_established');
  end if;

  if v_interface.resolver_kind='institutional_communication_endpoint' then
    select * into v_binding
    from atlas.addressable_subject_institution_bindings
    where addressable_subject_id=p_addressable_subject_id and binding_state='active'
    order by established_at desc
    limit 1;

    if v_binding.id is null then
      return jsonb_build_object('contractVersion','addressable_interface_resolution_v1','state','unavailable','reason','no_entity_authorized_binding');
    end if;

    select * into v_endpoint
    from atlas.communication_endpoints ep
    where ep.organization_id=v_binding.organization_id
      and ep.organization_unit_id is not distinct from v_binding.organization_unit_id
      and ep.endpoint_state='active'
      and ep.endpoint_kind in ('email','phone','sms','voice','web_form','social','atlas_native')
    order by case ep.endpoint_kind when 'atlas_native' then 1 when 'email' then 2 when 'web_form' then 3 when 'phone' then 4 else 5 end, ep.created_at
    limit 1;

    if v_endpoint.id is null then
      return jsonb_build_object('contractVersion','addressable_interface_resolution_v1','state','unavailable','reason','no_active_communication_endpoint');
    end if;

    return jsonb_build_object(
      'contractVersion','addressable_interface_resolution_v1',
      'state','resolved',
      'addressableSubjectId',p_addressable_subject_id,
      'interfaceKey',v_interface.stable_key,
      'resolverKind',v_interface.resolver_kind,
      'target',jsonb_build_object(
        'communicationEndpointId',v_endpoint.id,
        'endpointKind',v_endpoint.endpoint_kind,
        'address',v_endpoint.address,
        'displayName',v_endpoint.display_name
      ),
      'authorityPosition','entity_authorized'
    );
  end if;

  if v_interface.resolver_kind='source_attributed_external_route' then
    v_routes:=coalesce(v_interface.resolver_config->'routes','[]'::jsonb);
    if jsonb_typeof(v_routes)<>'array' or jsonb_array_length(v_routes)=0 then
      return jsonb_build_object('contractVersion','addressable_interface_resolution_v1','state','unavailable','reason','no_source_attributed_route');
    end if;
    return jsonb_build_object(
      'contractVersion','addressable_interface_resolution_v1',
      'state','resolved',
      'addressableSubjectId',p_addressable_subject_id,
      'interfaceKey',v_interface.stable_key,
      'resolverKind',v_interface.resolver_kind,
      'target',jsonb_build_object('routes',v_routes),
      'authorityPosition','externally_observed',
      'provenance',v_interface.publication_basis
    );
  end if;

  return jsonb_build_object('contractVersion','addressable_interface_resolution_v1','state','unavailable','reason','unsupported_resolver_kind');
end;
$function$;

-- Public RPC wrappers only; tables remain non-client-readable.
create or replace function public.resolve_addressable_subject_exact_self_api_v1(p_addressable_subject_id uuid)
returns jsonb
language sql
security invoker
set search_path = pg_catalog, atlas, public
as $$
  select atlas.resolve_addressable_subject_exact_self_api_v1(p_addressable_subject_id);
$$;

create or replace function public.resolve_addressable_interface_self_api_v1(p_addressable_subject_id uuid,p_interface_key text)
returns jsonb
language sql
security invoker
set search_path = pg_catalog, atlas, public
as $$
  select atlas.resolve_addressable_interface_self_api_v1(p_addressable_subject_id,p_interface_key);
$$;

-- ---------------------------------------------------------------------------
-- Privileges / RLS
-- ---------------------------------------------------------------------------

alter table atlas.addressable_subjects enable row level security;
alter table atlas.addressable_subject_institution_bindings enable row level security;
alter table atlas.addressable_interfaces enable row level security;
alter table atlas.addressable_subject_local_assertions enable row level security;

revoke all on atlas.addressable_subjects from public, anon, authenticated;
revoke all on atlas.addressable_subject_institution_bindings from public, anon, authenticated;
revoke all on atlas.addressable_interfaces from public, anon, authenticated;
revoke all on atlas.addressable_subject_local_assertions from public, anon, authenticated;

revoke all on function atlas.establish_addressable_subject_for_institution_service_v1(uuid,uuid,text,jsonb) from public, anon, authenticated;
revoke all on function atlas.establish_external_addressable_subject_service_v1(text,jsonb) from public, anon, authenticated;
revoke all on function atlas.publish_addressable_interface_service_v1(uuid,text,text,text,text,jsonb,jsonb) from public, anon, authenticated;
grant execute on function atlas.establish_addressable_subject_for_institution_service_v1(uuid,uuid,text,jsonb) to service_role;
grant execute on function atlas.establish_external_addressable_subject_service_v1(text,jsonb) to service_role;
grant execute on function atlas.publish_addressable_interface_service_v1(uuid,text,text,text,text,jsonb,jsonb) to service_role;

revoke all on function atlas.resolve_addressable_subject_exact_self_api_v1(uuid) from public, anon;
revoke all on function atlas.resolve_addressable_interface_self_api_v1(uuid,text) from public, anon;
grant execute on function atlas.resolve_addressable_subject_exact_self_api_v1(uuid) to authenticated;
grant execute on function atlas.resolve_addressable_interface_self_api_v1(uuid,text) to authenticated;

revoke all on function public.resolve_addressable_subject_exact_self_api_v1(uuid) from public, anon;
revoke all on function public.resolve_addressable_interface_self_api_v1(uuid,text) from public, anon;
grant execute on function public.resolve_addressable_subject_exact_self_api_v1(uuid) to authenticated;
grant execute on function public.resolve_addressable_interface_self_api_v1(uuid,text) to authenticated;

COMMIT;
