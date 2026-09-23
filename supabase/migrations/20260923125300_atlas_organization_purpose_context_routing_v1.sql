-- Atlas Organization Purpose / Context Routing v1
-- Canonical reality remains in Shared Intelligence.
-- This package establishes Organization-private occurrence bindings and many-use routing.

create unique index if not exists external_relationships_org_id_id_uq
  on atlas.external_relationships(organization_id,id);

create table atlas.organization_occurrence_bindings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  occurrence_id uuid not null references local_intel.occurrences(id) on delete restrict,
  binding_state text not null default 'active'
    check (binding_state in ('active','inactive')),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_by_membership_id uuid null references atlas.organization_memberships(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, occurrence_id),
  unique (organization_id, id)
);

comment on table atlas.organization_occurrence_bindings is
  'Organization-private binding to one canonical local_intel occurrence. This is not event identity; local_intel.occurrences remains canonical occurrence authority.';

create table atlas.organization_purpose_contexts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  stable_key text not null,
  context_kind text not null,
  title text not null,
  description text null,
  context_state text not null default 'active'
    check (context_state in ('active','archived')),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_by_membership_id uuid null references atlas.organization_memberships(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, stable_key),
  unique (organization_id, id),
  check (btrim(stable_key) <> ''),
  check (stable_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  check (context_kind ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  check (btrim(title) <> '')
);

comment on table atlas.organization_purpose_contexts is
  'Organization-private durable purpose container: program, fundraiser, campaign, calendar, resource guide, donor set, roster, or another lawful internal use. Context is not identity.';

create table atlas.organization_purpose_context_memberships (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  context_id uuid not null,
  member_kind text not null
    check (member_kind in ('external_relationship','occurrence_binding')),
  external_relationship_id uuid null,
  occurrence_binding_id uuid null,
  membership_state text not null default 'active'
    check (membership_state in ('active','excluded','archived')),
  role_keys text[] not null default '{}'::text[],
  payload jsonb not null default '{}'::jsonb
    check (jsonb_typeof(payload)='object'),
  provenance jsonb not null default '{}'::jsonb
    check (jsonb_typeof(provenance)='object'),
  created_by_membership_id uuid null references atlas.organization_memberships(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint organization_purpose_context_memberships_context_org_fk
    foreign key (organization_id, context_id)
    references atlas.organization_purpose_contexts(organization_id,id)
    on delete cascade,

  constraint organization_purpose_context_memberships_relationship_org_fk
    foreign key (organization_id, external_relationship_id)
    references atlas.external_relationships(organization_id,id)
    on delete restrict,

  constraint organization_purpose_context_memberships_occurrence_binding_org_fk
    foreign key (organization_id, occurrence_binding_id)
    references atlas.organization_occurrence_bindings(organization_id,id)
    on delete restrict,

  constraint organization_purpose_context_memberships_referent_shape_check
    check (
      (member_kind='external_relationship'
        and external_relationship_id is not null
        and occurrence_binding_id is null)
      or
      (member_kind='occurrence_binding'
        and occurrence_binding_id is not null
        and external_relationship_id is null)
    )
);

create unique index organization_purpose_context_memberships_relationship_uq
  on atlas.organization_purpose_context_memberships(context_id,external_relationship_id)
  where external_relationship_id is not null;

create unique index organization_purpose_context_memberships_occurrence_uq
  on atlas.organization_purpose_context_memberships(context_id,occurrence_binding_id)
  where occurrence_binding_id is not null;

create index organization_purpose_contexts_org_kind_idx
  on atlas.organization_purpose_contexts(organization_id,context_kind,context_state);

create index organization_occurrence_bindings_org_state_idx
  on atlas.organization_occurrence_bindings(organization_id,binding_state);

create index organization_purpose_context_memberships_context_state_idx
  on atlas.organization_purpose_context_memberships(context_id,membership_state);

alter table atlas.organization_occurrence_bindings enable row level security;
alter table atlas.organization_purpose_contexts enable row level security;
alter table atlas.organization_purpose_context_memberships enable row level security;

revoke all on table atlas.organization_occurrence_bindings from public, anon, authenticated;
revoke all on table atlas.organization_purpose_contexts from public, anon, authenticated;
revoke all on table atlas.organization_purpose_context_memberships from public, anon, authenticated;

grant select,insert,update,delete on table atlas.organization_occurrence_bindings to service_role;
grant select,insert,update,delete on table atlas.organization_purpose_contexts to service_role;
grant select,insert,update,delete on table atlas.organization_purpose_context_memberships to service_role;

create or replace function atlas.create_purpose_context_service_v1(
  p_organization_id uuid,
  p_stable_key text,
  p_context_kind text,
  p_title text,
  p_description text default null,
  p_metadata jsonb default '{}'::jsonb,
  p_created_by_membership_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_key text:=lower(btrim(coalesce(p_stable_key,'')));
  v_kind text:=lower(btrim(coalesce(p_context_kind,'')));
  v_title text:=btrim(coalesce(p_title,''));
  v_context atlas.organization_purpose_contexts%rowtype;
begin
  if not exists(select 1 from atlas.organizations o where o.id=p_organization_id and o.status='active') then
    raise exception 'Organization not found or inactive.' using errcode='P0002';
  end if;
  if v_key='' or v_key !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$' then
    raise exception 'Invalid context stable key.' using errcode='22023';
  end if;
  if v_kind='' or v_kind !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$' then
    raise exception 'Invalid context kind.' using errcode='22023';
  end if;
  if v_title='' then
    raise exception 'Context title is required.' using errcode='22023';
  end if;
  if jsonb_typeof(coalesce(p_metadata,'{}'::jsonb)) <> 'object' then
    raise exception 'Context metadata must be a JSON object.' using errcode='22023';
  end if;
  if p_created_by_membership_id is not null
     and not exists(
       select 1 from atlas.organization_memberships om
       where om.id=p_created_by_membership_id and om.organization_id=p_organization_id
     ) then
    raise exception 'Creator membership is outside organization.' using errcode='42501';
  end if;

  select * into v_context
  from atlas.organization_purpose_contexts c
  where c.organization_id=p_organization_id and c.stable_key=v_key;

  if v_context.id is not null and v_context.context_kind <> v_kind then
    raise exception 'Existing context stable key has a different context kind.' using errcode='23514';
  end if;

  insert into atlas.organization_purpose_contexts(
    organization_id,stable_key,context_kind,title,description,context_state,
    metadata,created_by_membership_id
  ) values (
    p_organization_id,v_key,v_kind,v_title,nullif(btrim(coalesce(p_description,'')),''),
    'active',coalesce(p_metadata,'{}'::jsonb),p_created_by_membership_id
  )
  on conflict (organization_id,stable_key) do update
  set title=excluded.title,
      description=excluded.description,
      context_state='active',
      metadata=atlas.organization_purpose_contexts.metadata || excluded.metadata,
      updated_at=now()
  returning * into v_context;

  return jsonb_build_object(
    'contractVersion','organization_purpose_context_v1',
    'contextId',v_context.id,
    'organizationId',v_context.organization_id,
    'stableKey',v_context.stable_key,
    'contextKind',v_context.context_kind,
    'title',v_context.title,
    'contextState',v_context.context_state
  );
end
$function$;

create or replace function atlas.archive_purpose_context_service_v1(
  p_organization_id uuid,
  p_context_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_context atlas.organization_purpose_contexts%rowtype;
begin
  update atlas.organization_purpose_contexts c
  set context_state='archived', updated_at=now()
  where c.id=p_context_id and c.organization_id=p_organization_id
  returning * into v_context;

  if v_context.id is null then
    raise exception 'Purpose context is outside organization or missing.' using errcode='42501';
  end if;

  return jsonb_build_object(
    'contractVersion','archive_purpose_context_v1',
    'contextId',v_context.id,
    'organizationId',v_context.organization_id,
    'contextState',v_context.context_state
  );
end
$function$;

create or replace function atlas.bind_canonical_occurrence_service_v1(
  p_organization_id uuid,
  p_occurrence_id uuid,
  p_metadata jsonb default '{}'::jsonb,
  p_created_by_membership_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_binding atlas.organization_occurrence_bindings%rowtype;
begin
  if not exists(select 1 from atlas.organizations o where o.id=p_organization_id and o.status='active') then
    raise exception 'Organization not found or inactive.' using errcode='P0002';
  end if;
  if not exists(select 1 from local_intel.occurrences o where o.id=p_occurrence_id) then
    raise exception 'Canonical occurrence not found.' using errcode='P0002';
  end if;
  if jsonb_typeof(coalesce(p_metadata,'{}'::jsonb)) <> 'object' then
    raise exception 'Occurrence binding metadata must be a JSON object.' using errcode='22023';
  end if;
  if p_created_by_membership_id is not null
     and not exists(
       select 1 from atlas.organization_memberships om
       where om.id=p_created_by_membership_id and om.organization_id=p_organization_id
     ) then
    raise exception 'Creator membership is outside organization.' using errcode='42501';
  end if;

  insert into atlas.organization_occurrence_bindings(
    organization_id,occurrence_id,binding_state,metadata,created_by_membership_id
  ) values (
    p_organization_id,p_occurrence_id,'active',coalesce(p_metadata,'{}'::jsonb),
    p_created_by_membership_id
  )
  on conflict (organization_id,occurrence_id) do update
  set binding_state='active',
      metadata=atlas.organization_occurrence_bindings.metadata || excluded.metadata,
      updated_at=now()
  returning * into v_binding;

  return jsonb_build_object(
    'contractVersion','organization_occurrence_binding_v1',
    'bindingId',v_binding.id,
    'organizationId',v_binding.organization_id,
    'occurrenceId',v_binding.occurrence_id,
    'bindingState',v_binding.binding_state
  );
end
$function$;

create or replace function atlas.add_external_relationship_to_purpose_context_service_v1(
  p_organization_id uuid,
  p_context_id uuid,
  p_external_relationship_id uuid,
  p_role_keys text[] default '{}'::text[],
  p_payload jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb,
  p_created_by_membership_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_roles text[];
  v_membership atlas.organization_purpose_context_memberships%rowtype;
begin
  if not exists(
    select 1 from atlas.organization_purpose_contexts c
    where c.id=p_context_id and c.organization_id=p_organization_id and c.context_state='active'
  ) then
    raise exception 'Active purpose context is outside organization or missing.' using errcode='42501';
  end if;
  if not exists(
    select 1 from atlas.external_relationships r
    where r.id=p_external_relationship_id and r.organization_id=p_organization_id
  ) then
    raise exception 'External relationship is outside organization or missing.' using errcode='42501';
  end if;
  if jsonb_typeof(coalesce(p_payload,'{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(p_provenance,'{}'::jsonb)) <> 'object' then
    raise exception 'Membership payload and provenance must be JSON objects.' using errcode='22023';
  end if;
  if p_created_by_membership_id is not null
     and not exists(
       select 1 from atlas.organization_memberships om
       where om.id=p_created_by_membership_id and om.organization_id=p_organization_id
     ) then
    raise exception 'Creator membership is outside organization.' using errcode='42501';
  end if;

  select coalesce(array_agg(x.role_key order by x.role_key),'{}'::text[])
  into v_roles
  from (
    select distinct lower(btrim(v)) as role_key
    from unnest(coalesce(p_role_keys,'{}'::text[])) v
    where btrim(v) <> ''
      and lower(btrim(v)) ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
  ) x;

  insert into atlas.organization_purpose_context_memberships(
    organization_id,context_id,member_kind,external_relationship_id,
    membership_state,role_keys,payload,provenance,created_by_membership_id
  ) values (
    p_organization_id,p_context_id,'external_relationship',p_external_relationship_id,
    'active',v_roles,coalesce(p_payload,'{}'::jsonb),coalesce(p_provenance,'{}'::jsonb),
    p_created_by_membership_id
  )
  on conflict (context_id,external_relationship_id)
    where external_relationship_id is not null
  do update set
    membership_state='active',
    role_keys=excluded.role_keys,
    payload=excluded.payload,
    provenance=excluded.provenance,
    created_by_membership_id=coalesce(excluded.created_by_membership_id,atlas.organization_purpose_context_memberships.created_by_membership_id),
    updated_at=now()
  returning * into v_membership;

  return jsonb_build_object(
    'contractVersion','purpose_context_membership_v1',
    'membershipId',v_membership.id,
    'contextId',v_membership.context_id,
    'memberKind',v_membership.member_kind,
    'externalRelationshipId',v_membership.external_relationship_id,
    'membershipState',v_membership.membership_state,
    'roleKeys',to_jsonb(v_membership.role_keys),
    'payload',v_membership.payload
  );
end
$function$;

create or replace function atlas.add_occurrence_to_purpose_context_service_v1(
  p_organization_id uuid,
  p_context_id uuid,
  p_occurrence_binding_id uuid,
  p_role_keys text[] default '{}'::text[],
  p_payload jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb,
  p_created_by_membership_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_roles text[];
  v_membership atlas.organization_purpose_context_memberships%rowtype;
begin
  if not exists(
    select 1 from atlas.organization_purpose_contexts c
    where c.id=p_context_id and c.organization_id=p_organization_id and c.context_state='active'
  ) then
    raise exception 'Active purpose context is outside organization or missing.' using errcode='42501';
  end if;
  if not exists(
    select 1 from atlas.organization_occurrence_bindings b
    where b.id=p_occurrence_binding_id and b.organization_id=p_organization_id and b.binding_state='active'
  ) then
    raise exception 'Active occurrence binding is outside organization or missing.' using errcode='42501';
  end if;
  if jsonb_typeof(coalesce(p_payload,'{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(p_provenance,'{}'::jsonb)) <> 'object' then
    raise exception 'Membership payload and provenance must be JSON objects.' using errcode='22023';
  end if;
  if p_created_by_membership_id is not null
     and not exists(
       select 1 from atlas.organization_memberships om
       where om.id=p_created_by_membership_id and om.organization_id=p_organization_id
     ) then
    raise exception 'Creator membership is outside organization.' using errcode='42501';
  end if;

  select coalesce(array_agg(x.role_key order by x.role_key),'{}'::text[])
  into v_roles
  from (
    select distinct lower(btrim(v)) as role_key
    from unnest(coalesce(p_role_keys,'{}'::text[])) v
    where btrim(v) <> ''
      and lower(btrim(v)) ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
  ) x;

  insert into atlas.organization_purpose_context_memberships(
    organization_id,context_id,member_kind,occurrence_binding_id,
    membership_state,role_keys,payload,provenance,created_by_membership_id
  ) values (
    p_organization_id,p_context_id,'occurrence_binding',p_occurrence_binding_id,
    'active',v_roles,coalesce(p_payload,'{}'::jsonb),coalesce(p_provenance,'{}'::jsonb),
    p_created_by_membership_id
  )
  on conflict (context_id,occurrence_binding_id)
    where occurrence_binding_id is not null
  do update set
    membership_state='active',
    role_keys=excluded.role_keys,
    payload=excluded.payload,
    provenance=excluded.provenance,
    created_by_membership_id=coalesce(excluded.created_by_membership_id,atlas.organization_purpose_context_memberships.created_by_membership_id),
    updated_at=now()
  returning * into v_membership;

  return jsonb_build_object(
    'contractVersion','purpose_context_membership_v1',
    'membershipId',v_membership.id,
    'contextId',v_membership.context_id,
    'memberKind',v_membership.member_kind,
    'occurrenceBindingId',v_membership.occurrence_binding_id,
    'membershipState',v_membership.membership_state,
    'roleKeys',to_jsonb(v_membership.role_keys),
    'payload',v_membership.payload
  );
end
$function$;

create or replace function atlas.remove_external_relationship_from_purpose_context_service_v1(
  p_organization_id uuid,
  p_context_id uuid,
  p_external_relationship_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_membership atlas.organization_purpose_context_memberships%rowtype;
begin
  update atlas.organization_purpose_context_memberships m
  set membership_state='archived', updated_at=now()
  where m.organization_id=p_organization_id
    and m.context_id=p_context_id
    and m.external_relationship_id=p_external_relationship_id
  returning * into v_membership;

  return jsonb_build_object(
    'contractVersion','remove_purpose_context_membership_v1',
    'removed',v_membership.id is not null,
    'membershipId',v_membership.id,
    'contextId',p_context_id,
    'externalRelationshipId',p_external_relationship_id
  );
end
$function$;

create or replace function atlas.remove_occurrence_from_purpose_context_service_v1(
  p_organization_id uuid,
  p_context_id uuid,
  p_occurrence_binding_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_membership atlas.organization_purpose_context_memberships%rowtype;
begin
  update atlas.organization_purpose_context_memberships m
  set membership_state='archived', updated_at=now()
  where m.organization_id=p_organization_id
    and m.context_id=p_context_id
    and m.occurrence_binding_id=p_occurrence_binding_id
  returning * into v_membership;

  return jsonb_build_object(
    'contractVersion','remove_purpose_context_membership_v1',
    'removed',v_membership.id is not null,
    'membershipId',v_membership.id,
    'contextId',p_context_id,
    'occurrenceBindingId',p_occurrence_binding_id
  );
end
$function$;

create or replace function atlas.purpose_context_detail_service_v1(
  p_organization_id uuid,
  p_context_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_context atlas.organization_purpose_contexts%rowtype;
  v_members jsonb;
begin
  select * into v_context
  from atlas.organization_purpose_contexts c
  where c.id=p_context_id and c.organization_id=p_organization_id;

  if v_context.id is null then
    raise exception 'Purpose context is outside organization or missing.' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'membershipId',m.id,
      'memberKind',m.member_kind,
      'membershipState',m.membership_state,
      'roleKeys',to_jsonb(m.role_keys),
      'payload',m.payload,
      'provenance',m.provenance,
      'externalRelationshipId',m.external_relationship_id,
      'occurrenceBindingId',m.occurrence_binding_id,
      'canonicalEntity',case when m.member_kind='external_relationship' then (
        select jsonb_build_object(
          'entityId',e.id,
          'entityType',e.entity_type,
          'name',e.name,
          'websiteUrl',e.website_url,
          'phone',e.phone,
          'email',e.email,
          'city',e.city,
          'state',e.state
        )
        from atlas.external_relationships r
        join atlas.identity_subject_external_identifiers i
          on i.organization_id=r.organization_id
         and i.subject_id=r.subject_id
         and i.provider_key='local_intel'
         and i.identifier_type='entity_id'
         and i.is_current
        join local_intel.entities e on e.id::text=i.identifier_normalized
        where r.id=m.external_relationship_id
          and r.organization_id=m.organization_id
        order by i.priority,i.created_at,i.id
        limit 1
      ) else null end,
      'canonicalOccurrence',case when m.member_kind='occurrence_binding' then (
        select jsonb_build_object(
          'occurrenceId',o.id,
          'title',o.title,
          'occurrenceType',o.occurrence_type,
          'startAt',o.start_at,
          'endAt',o.end_at,
          'status',o.status,
          'venueName',o.venue_name,
          'city',o.city,
          'state',o.state,
          'hostEntityId',o.entity_id,
          'hostName',e.name
        )
        from atlas.organization_occurrence_bindings b
        join local_intel.occurrences o on o.id=b.occurrence_id
        left join local_intel.entities e on e.id=o.entity_id
        where b.id=m.occurrence_binding_id
          and b.organization_id=m.organization_id
      ) else null end
    ) order by m.created_at,m.id
  ),'[]'::jsonb)
  into v_members
  from atlas.organization_purpose_context_memberships m
  where m.organization_id=p_organization_id
    and m.context_id=p_context_id;

  return jsonb_build_object(
    'contractVersion','purpose_context_detail_v1',
    'context',jsonb_build_object(
      'contextId',v_context.id,
      'organizationId',v_context.organization_id,
      'stableKey',v_context.stable_key,
      'contextKind',v_context.context_kind,
      'title',v_context.title,
      'description',v_context.description,
      'contextState',v_context.context_state,
      'metadata',v_context.metadata
    ),
    'members',v_members
  );
end
$function$;

-- Authenticated self APIs: all authorization resolves from current effective Organization membership.

create or replace function atlas.create_purpose_context_self_api_v1(
  p_organization_id uuid,
  p_stable_key text,
  p_context_kind text,
  p_title text,
  p_description text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare v_membership_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required.' using errcode='28000';
  end if;
  v_membership_id:=atlas.current_effective_organization_membership_v1(p_organization_id);
  if v_membership_id is null then
    raise exception 'Organization access denied.' using errcode='42501';
  end if;
  return atlas.create_purpose_context_service_v1(
    p_organization_id,p_stable_key,p_context_kind,p_title,p_description,p_metadata,v_membership_id
  );
end
$function$;

create or replace function atlas.archive_purpose_context_self_api_v1(
  p_organization_id uuid,
  p_context_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='28000'; end if;
  if atlas.current_effective_organization_membership_v1(p_organization_id) is null then
    raise exception 'Organization access denied.' using errcode='42501';
  end if;
  return atlas.archive_purpose_context_service_v1(p_organization_id,p_context_id);
end
$function$;

create or replace function atlas.bind_canonical_occurrence_self_api_v1(
  p_organization_id uuid,
  p_occurrence_id uuid,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare v_membership_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='28000'; end if;
  v_membership_id:=atlas.current_effective_organization_membership_v1(p_organization_id);
  if v_membership_id is null then raise exception 'Organization access denied.' using errcode='42501'; end if;
  return atlas.bind_canonical_occurrence_service_v1(
    p_organization_id,p_occurrence_id,p_metadata,v_membership_id
  );
end
$function$;

create or replace function atlas.add_external_relationship_to_purpose_context_self_api_v1(
  p_organization_id uuid,
  p_context_id uuid,
  p_external_relationship_id uuid,
  p_role_keys text[] default '{}'::text[],
  p_payload jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare v_membership_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='28000'; end if;
  v_membership_id:=atlas.current_effective_organization_membership_v1(p_organization_id);
  if v_membership_id is null then raise exception 'Organization access denied.' using errcode='42501'; end if;
  return atlas.add_external_relationship_to_purpose_context_service_v1(
    p_organization_id,p_context_id,p_external_relationship_id,p_role_keys,p_payload,p_provenance,v_membership_id
  );
end
$function$;

create or replace function atlas.add_occurrence_to_purpose_context_self_api_v1(
  p_organization_id uuid,
  p_context_id uuid,
  p_occurrence_binding_id uuid,
  p_role_keys text[] default '{}'::text[],
  p_payload jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare v_membership_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='28000'; end if;
  v_membership_id:=atlas.current_effective_organization_membership_v1(p_organization_id);
  if v_membership_id is null then raise exception 'Organization access denied.' using errcode='42501'; end if;
  return atlas.add_occurrence_to_purpose_context_service_v1(
    p_organization_id,p_context_id,p_occurrence_binding_id,p_role_keys,p_payload,p_provenance,v_membership_id
  );
end
$function$;

create or replace function atlas.remove_external_relationship_from_purpose_context_self_api_v1(
  p_organization_id uuid,
  p_context_id uuid,
  p_external_relationship_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='28000'; end if;
  if atlas.current_effective_organization_membership_v1(p_organization_id) is null then
    raise exception 'Organization access denied.' using errcode='42501';
  end if;
  return atlas.remove_external_relationship_from_purpose_context_service_v1(
    p_organization_id,p_context_id,p_external_relationship_id
  );
end
$function$;

create or replace function atlas.remove_occurrence_from_purpose_context_self_api_v1(
  p_organization_id uuid,
  p_context_id uuid,
  p_occurrence_binding_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='28000'; end if;
  if atlas.current_effective_organization_membership_v1(p_organization_id) is null then
    raise exception 'Organization access denied.' using errcode='42501';
  end if;
  return atlas.remove_occurrence_from_purpose_context_service_v1(
    p_organization_id,p_context_id,p_occurrence_binding_id
  );
end
$function$;

create or replace function atlas.purpose_context_detail_self_api_v1(
  p_organization_id uuid,
  p_context_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='28000'; end if;
  if atlas.current_effective_organization_membership_v1(p_organization_id) is null then
    raise exception 'Organization access denied.' using errcode='42501';
  end if;
  return atlas.purpose_context_detail_service_v1(p_organization_id,p_context_id);
end
$function$;

revoke all on function atlas.create_purpose_context_service_v1(uuid,text,text,text,text,jsonb,uuid) from public,anon,authenticated;
revoke all on function atlas.archive_purpose_context_service_v1(uuid,uuid) from public,anon,authenticated;
revoke all on function atlas.bind_canonical_occurrence_service_v1(uuid,uuid,jsonb,uuid) from public,anon,authenticated;
revoke all on function atlas.add_external_relationship_to_purpose_context_service_v1(uuid,uuid,uuid,text[],jsonb,jsonb,uuid) from public,anon,authenticated;
revoke all on function atlas.add_occurrence_to_purpose_context_service_v1(uuid,uuid,uuid,text[],jsonb,jsonb,uuid) from public,anon,authenticated;
revoke all on function atlas.remove_external_relationship_from_purpose_context_service_v1(uuid,uuid,uuid) from public,anon,authenticated;
revoke all on function atlas.remove_occurrence_from_purpose_context_service_v1(uuid,uuid,uuid) from public,anon,authenticated;
revoke all on function atlas.purpose_context_detail_service_v1(uuid,uuid) from public,anon,authenticated;

grant execute on function atlas.create_purpose_context_service_v1(uuid,text,text,text,text,jsonb,uuid) to service_role;
grant execute on function atlas.archive_purpose_context_service_v1(uuid,uuid) to service_role;
grant execute on function atlas.bind_canonical_occurrence_service_v1(uuid,uuid,jsonb,uuid) to service_role;
grant execute on function atlas.add_external_relationship_to_purpose_context_service_v1(uuid,uuid,uuid,text[],jsonb,jsonb,uuid) to service_role;
grant execute on function atlas.add_occurrence_to_purpose_context_service_v1(uuid,uuid,uuid,text[],jsonb,jsonb,uuid) to service_role;
grant execute on function atlas.remove_external_relationship_from_purpose_context_service_v1(uuid,uuid,uuid) to service_role;
grant execute on function atlas.remove_occurrence_from_purpose_context_service_v1(uuid,uuid,uuid) to service_role;
grant execute on function atlas.purpose_context_detail_service_v1(uuid,uuid) to service_role;

revoke all on function atlas.create_purpose_context_self_api_v1(uuid,text,text,text,text,jsonb) from public,anon;
revoke all on function atlas.archive_purpose_context_self_api_v1(uuid,uuid) from public,anon;
revoke all on function atlas.bind_canonical_occurrence_self_api_v1(uuid,uuid,jsonb) from public,anon;
revoke all on function atlas.add_external_relationship_to_purpose_context_self_api_v1(uuid,uuid,uuid,text[],jsonb,jsonb) from public,anon;
revoke all on function atlas.add_occurrence_to_purpose_context_self_api_v1(uuid,uuid,uuid,text[],jsonb,jsonb) from public,anon;
revoke all on function atlas.remove_external_relationship_from_purpose_context_self_api_v1(uuid,uuid,uuid) from public,anon;
revoke all on function atlas.remove_occurrence_from_purpose_context_self_api_v1(uuid,uuid,uuid) from public,anon;
revoke all on function atlas.purpose_context_detail_self_api_v1(uuid,uuid) from public,anon;

grant execute on function atlas.create_purpose_context_self_api_v1(uuid,text,text,text,text,jsonb) to authenticated;
grant execute on function atlas.archive_purpose_context_self_api_v1(uuid,uuid) to authenticated;
grant execute on function atlas.bind_canonical_occurrence_self_api_v1(uuid,uuid,jsonb) to authenticated;
grant execute on function atlas.add_external_relationship_to_purpose_context_self_api_v1(uuid,uuid,uuid,text[],jsonb,jsonb) to authenticated;
grant execute on function atlas.add_occurrence_to_purpose_context_self_api_v1(uuid,uuid,uuid,text[],jsonb,jsonb) to authenticated;
grant execute on function atlas.remove_external_relationship_from_purpose_context_self_api_v1(uuid,uuid,uuid) to authenticated;
grant execute on function atlas.remove_occurrence_from_purpose_context_self_api_v1(uuid,uuid,uuid) to authenticated;
grant execute on function atlas.purpose_context_detail_self_api_v1(uuid,uuid) to authenticated;

comment on function atlas.create_purpose_context_service_v1(uuid,text,text,text,text,jsonb,uuid) is
  'Creates/reactivates one Organization-private durable purpose context. Context is use, not identity.';
comment on function atlas.bind_canonical_occurrence_service_v1(uuid,uuid,jsonb,uuid) is
  'Binds one Atlas Organization privately to one canonical local_intel occurrence without cloning event identity.';
comment on function atlas.add_external_relationship_to_purpose_context_service_v1(uuid,uuid,uuid,text[],jsonb,jsonb,uuid) is
  'Routes an existing Organization external relationship into one purpose context with context-local payload.';
comment on function atlas.add_occurrence_to_purpose_context_service_v1(uuid,uuid,uuid,text[],jsonb,jsonb,uuid) is
  'Routes an existing Organization occurrence binding into one purpose context with context-local payload.';
comment on function atlas.purpose_context_detail_service_v1(uuid,uuid) is
  'Reads one Organization-private purpose context and composes its memberships with canonical Shared Intelligence facts.';
