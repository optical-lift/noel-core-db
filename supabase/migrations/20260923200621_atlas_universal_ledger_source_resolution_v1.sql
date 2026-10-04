-- Atlas universal Ledger source representation + canonical resolution kernel v1.
-- Reuses the existing atlas.ledgers / principal authority / organization
-- participation architecture. Canonical identity is universal; source
-- representation and private payload stay in Ledger custody.

create table if not exists atlas.ledger_source_connections (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references atlas.ledgers(id) on delete cascade,
  provider_key text not null,
  provider_account_key text not null,
  display_label text,
  connection_state text not null default 'active',
  authority_scope jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  connected_by_principal_id uuid references atlas.principals(id) on delete set null,
  connected_at timestamptz not null default now(),
  last_synced_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (ledger_id,id),
  unique (ledger_id,provider_key,provider_account_key),
  constraint ledger_source_connections_provider_key_v1
    check (provider_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint ledger_source_connections_account_nonblank_v1
    check (btrim(provider_account_key) <> ''),
  constraint ledger_source_connections_state_v1
    check (connection_state in ('active','paused','revoked','error')),
  constraint ledger_source_connections_authority_v1
    check (jsonb_typeof(authority_scope)='object'),
  constraint ledger_source_connections_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

comment on table atlas.ledger_source_connections is
  'Authorized external-system account within one existing Atlas Ledger. No OAuth tokens, passwords, refresh secrets, or provider credentials belong here.';

create table if not exists atlas.ledger_source_party_records (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references atlas.ledgers(id) on delete cascade,
  source_connection_id uuid not null,
  provider_record_type text not null,
  provider_record_id text not null,
  display_name text,
  source_record_state text not null default 'current',
  source_payload jsonb not null default '{}'::jsonb,
  payload_hash text,
  observed_at timestamptz not null default now(),
  source_updated_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (ledger_id,id),
  unique (source_connection_id,provider_record_type,provider_record_id),
  constraint ledger_source_party_records_connection_ledger_fk_v1
    foreign key (ledger_id,source_connection_id)
    references atlas.ledger_source_connections(ledger_id,id)
    on delete cascade,
  constraint ledger_source_party_records_type_v1
    check (provider_record_type ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint ledger_source_party_records_id_nonblank_v1
    check (btrim(provider_record_id) <> ''),
  constraint ledger_source_party_records_state_v1
    check (source_record_state in ('current','deleted','unavailable')),
  constraint ledger_source_party_records_payload_v1
    check (jsonb_typeof(source_payload)='object'),
  constraint ledger_source_party_records_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

comment on table atlas.ledger_source_party_records is
  'Ledger-private representation of a person/business/organization supplied by one connected source. It is not canonical identity authority.';

create index if not exists ledger_source_party_records_ledger_state_idx_v1
  on atlas.ledger_source_party_records(ledger_id,source_record_state,updated_at desc);

create table if not exists atlas.ledger_source_party_resolutions (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references atlas.ledgers(id) on delete cascade,
  source_party_record_id uuid not null,
  canonical_entity_id uuid not null references local_intel.entities(id) on delete restrict,
  is_current boolean not null default true,
  resolution_method text not null,
  confidence numeric(5,4) not null default 1.0000,
  resolver_version text,
  resolution_basis jsonb not null default '{}'::jsonb,
  established_by_principal_id uuid references atlas.principals(id) on delete set null,
  established_at timestamptz not null default now(),
  superseded_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint ledger_source_party_resolutions_record_ledger_fk_v1
    foreign key (ledger_id,source_party_record_id)
    references atlas.ledger_source_party_records(ledger_id,id)
    on delete cascade,
  constraint ledger_source_party_resolutions_method_v1
    check (resolution_method ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint ledger_source_party_resolutions_confidence_v1
    check (confidence >= 0 and confidence <= 1),
  constraint ledger_source_party_resolutions_current_shape_v1
    check ((is_current and superseded_at is null) or (not is_current)),
  constraint ledger_source_party_resolutions_basis_v1
    check (jsonb_typeof(resolution_basis)='object'),
  constraint ledger_source_party_resolutions_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

create unique index if not exists ledger_source_party_resolutions_current_uq_v1
  on atlas.ledger_source_party_resolutions(source_party_record_id)
  where is_current;

create index if not exists ledger_source_party_resolutions_entity_idx_v1
  on atlas.ledger_source_party_resolutions(canonical_entity_id,ledger_id)
  where is_current;

comment on table atlas.ledger_source_party_resolutions is
  'Private source-record→canonical-entity resolution history. Many records and many Ledgers may resolve to the same canonical entity without disclosing the other Ledgers.';

alter table atlas.ledger_source_connections enable row level security;
alter table atlas.ledger_source_party_records enable row level security;
alter table atlas.ledger_source_party_resolutions enable row level security;

revoke all on table atlas.ledger_source_connections from public,anon,authenticated;
revoke all on table atlas.ledger_source_party_records from public,anon,authenticated;
revoke all on table atlas.ledger_source_party_resolutions from public,anon,authenticated;

grant select,insert,update,delete on table atlas.ledger_source_connections to service_role;
grant select,insert,update,delete on table atlas.ledger_source_party_records to service_role;
grant select,insert,update,delete on table atlas.ledger_source_party_resolutions to service_role;

create or replace function atlas.set_ledger_source_updated_at_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','atlas'
as $function$
begin
  new.updated_at=now();
  return new;
end
$function$;

drop trigger if exists ledger_source_connections_updated_at_v1
  on atlas.ledger_source_connections;
create trigger ledger_source_connections_updated_at_v1
before update on atlas.ledger_source_connections
for each row execute function atlas.set_ledger_source_updated_at_v1();

drop trigger if exists ledger_source_party_records_updated_at_v1
  on atlas.ledger_source_party_records;
create trigger ledger_source_party_records_updated_at_v1
before update on atlas.ledger_source_party_records
for each row execute function atlas.set_ledger_source_updated_at_v1();

create or replace function atlas.upsert_ledger_source_connection_service_v1(
  p_ledger_id uuid,
  p_provider_key text,
  p_provider_account_key text,
  p_display_label text default null,
  p_authority_scope jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb,
  p_connected_by_principal_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_provider text:=lower(btrim(coalesce(p_provider_key,'')));
  v_conn atlas.ledger_source_connections%rowtype;
begin
  if not exists(
    select 1 from atlas.ledgers l
    where l.id=p_ledger_id and l.status='active'
  ) then
    raise exception 'Active Ledger not found.' using errcode='P0002';
  end if;

  if v_provider !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$' then
    raise exception 'Provider key must be normalized.' using errcode='22023';
  end if;

  if btrim(coalesce(p_provider_account_key,''))='' then
    raise exception 'Provider account key is required.' using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_authority_scope,'{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(p_metadata,'{}'::jsonb)) <> 'object' then
    raise exception 'Authority scope and metadata must be JSON objects.'
      using errcode='22023';
  end if;

  if p_connected_by_principal_id is not null
     and not atlas.principal_has_ledger_authority_v1(
       p_connected_by_principal_id,p_ledger_id
     ) then
    raise exception 'Principal lacks authority over Ledger.'
      using errcode='42501';
  end if;

  insert into atlas.ledger_source_connections(
    ledger_id,provider_key,provider_account_key,display_label,
    connection_state,authority_scope,metadata,connected_by_principal_id
  )
  values(
    p_ledger_id,v_provider,btrim(p_provider_account_key),
    nullif(btrim(p_display_label),''),
    'active',coalesce(p_authority_scope,'{}'::jsonb),
    coalesce(p_metadata,'{}'::jsonb),p_connected_by_principal_id
  )
  on conflict (ledger_id,provider_key,provider_account_key)
  do update set
    display_label=coalesce(excluded.display_label,atlas.ledger_source_connections.display_label),
    connection_state='active',
    authority_scope=excluded.authority_scope,
    metadata=atlas.ledger_source_connections.metadata || excluded.metadata,
    connected_by_principal_id=coalesce(
      excluded.connected_by_principal_id,
      atlas.ledger_source_connections.connected_by_principal_id
    ),
    updated_at=now()
  returning * into v_conn;

  return jsonb_build_object(
    'contractVersion','ledger_source_connection_v1',
    'sourceConnectionId',v_conn.id,
    'ledgerId',v_conn.ledger_id,
    'providerKey',v_conn.provider_key,
    'providerAccountKey',v_conn.provider_account_key,
    'connectionState',v_conn.connection_state
  );
end
$function$;

create or replace function atlas.upsert_ledger_source_party_record_service_v1(
  p_ledger_id uuid,
  p_source_connection_id uuid,
  p_provider_record_type text,
  p_provider_record_id text,
  p_display_name text default null,
  p_source_payload jsonb default '{}'::jsonb,
  p_payload_hash text default null,
  p_observed_at timestamptz default now(),
  p_source_updated_at timestamptz default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_type text:=lower(btrim(coalesce(p_provider_record_type,'')));
  v_record atlas.ledger_source_party_records%rowtype;
begin
  if not exists(
    select 1
    from atlas.ledger_source_connections c
    where c.id=p_source_connection_id
      and c.ledger_id=p_ledger_id
      and c.connection_state in ('active','paused')
  ) then
    raise exception 'Source connection is outside Ledger or unavailable.'
      using errcode='42501';
  end if;

  if v_type !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$' then
    raise exception 'Provider record type must be normalized.'
      using errcode='22023';
  end if;

  if btrim(coalesce(p_provider_record_id,''))='' then
    raise exception 'Provider record ID is required.' using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_source_payload,'{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(p_metadata,'{}'::jsonb)) <> 'object' then
    raise exception 'Source payload and metadata must be JSON objects.'
      using errcode='22023';
  end if;

  insert into atlas.ledger_source_party_records(
    ledger_id,source_connection_id,provider_record_type,provider_record_id,
    display_name,source_record_state,source_payload,payload_hash,
    observed_at,source_updated_at,metadata
  )
  values(
    p_ledger_id,p_source_connection_id,v_type,btrim(p_provider_record_id),
    nullif(btrim(p_display_name),''),'current',
    coalesce(p_source_payload,'{}'::jsonb),nullif(btrim(p_payload_hash),''),
    coalesce(p_observed_at,now()),p_source_updated_at,
    coalesce(p_metadata,'{}'::jsonb)
  )
  on conflict (source_connection_id,provider_record_type,provider_record_id)
  do update set
    display_name=coalesce(excluded.display_name,atlas.ledger_source_party_records.display_name),
    source_record_state='current',
    source_payload=excluded.source_payload,
    payload_hash=excluded.payload_hash,
    observed_at=excluded.observed_at,
    source_updated_at=excluded.source_updated_at,
    metadata=atlas.ledger_source_party_records.metadata || excluded.metadata,
    updated_at=now()
  returning * into v_record;

  return jsonb_build_object(
    'contractVersion','ledger_source_party_record_v1',
    'sourcePartyRecordId',v_record.id,
    'ledgerId',v_record.ledger_id,
    'sourceConnectionId',v_record.source_connection_id,
    'providerRecordType',v_record.provider_record_type,
    'providerRecordId',v_record.provider_record_id,
    'sourceRecordState',v_record.source_record_state
  );
end
$function$;

create or replace function atlas.resolve_ledger_source_party_record_service_v1(
  p_ledger_id uuid,
  p_source_party_record_id uuid,
  p_canonical_entity_id uuid,
  p_resolution_method text,
  p_confidence numeric default 1.0,
  p_resolver_version text default null,
  p_resolution_basis jsonb default '{}'::jsonb,
  p_established_by_principal_id uuid default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_method text:=lower(btrim(coalesce(p_resolution_method,'')));
  v_resolution atlas.ledger_source_party_resolutions%rowtype;
begin
  if not exists(
    select 1
    from atlas.ledger_source_party_records r
    where r.id=p_source_party_record_id
      and r.ledger_id=p_ledger_id
      and r.source_record_state='current'
  ) then
    raise exception 'Current source party record is outside Ledger or missing.'
      using errcode='42501';
  end if;

  if not exists(
    select 1 from local_intel.entities e
    where e.id=p_canonical_entity_id
  ) then
    raise exception 'Canonical entity not found.' using errcode='P0002';
  end if;

  if v_method !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$' then
    raise exception 'Resolution method must be normalized.'
      using errcode='22023';
  end if;

  if p_confidence < 0 or p_confidence > 1 then
    raise exception 'Resolution confidence must be between 0 and 1.'
      using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_resolution_basis,'{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(p_metadata,'{}'::jsonb)) <> 'object' then
    raise exception 'Resolution basis and metadata must be JSON objects.'
      using errcode='22023';
  end if;

  if p_established_by_principal_id is not null
     and not atlas.principal_has_ledger_authority_v1(
       p_established_by_principal_id,p_ledger_id
     ) then
    raise exception 'Principal lacks authority over Ledger.'
      using errcode='42501';
  end if;

  select *
  into v_resolution
  from atlas.ledger_source_party_resolutions x
  where x.source_party_record_id=p_source_party_record_id
    and x.is_current
  limit 1;

  if v_resolution.id is not null
     and v_resolution.canonical_entity_id=p_canonical_entity_id then
    update atlas.ledger_source_party_resolutions x
    set resolution_method=v_method,
        confidence=p_confidence,
        resolver_version=nullif(btrim(p_resolver_version),''),
        resolution_basis=x.resolution_basis || coalesce(p_resolution_basis,'{}'::jsonb),
        established_by_principal_id=coalesce(
          p_established_by_principal_id,x.established_by_principal_id
        ),
        metadata=x.metadata || coalesce(p_metadata,'{}'::jsonb)
    where x.id=v_resolution.id
    returning * into v_resolution;
  else
    if v_resolution.id is not null then
      update atlas.ledger_source_party_resolutions
      set is_current=false,
          superseded_at=now()
      where id=v_resolution.id;
    end if;

    insert into atlas.ledger_source_party_resolutions(
      ledger_id,source_party_record_id,canonical_entity_id,is_current,
      resolution_method,confidence,resolver_version,resolution_basis,
      established_by_principal_id,metadata
    )
    values(
      p_ledger_id,p_source_party_record_id,p_canonical_entity_id,true,
      v_method,p_confidence,nullif(btrim(p_resolver_version),''),
      coalesce(p_resolution_basis,'{}'::jsonb),
      p_established_by_principal_id,coalesce(p_metadata,'{}'::jsonb)
    )
    returning * into v_resolution;
  end if;

  return jsonb_build_object(
    'contractVersion','ledger_source_party_resolution_v1',
    'resolutionId',v_resolution.id,
    'ledgerId',v_resolution.ledger_id,
    'sourcePartyRecordId',v_resolution.source_party_record_id,
    'canonicalEntityId',v_resolution.canonical_entity_id,
    'resolutionMethod',v_resolution.resolution_method,
    'confidence',v_resolution.confidence,
    'isCurrent',v_resolution.is_current
  );
end
$function$;

create or replace function atlas.ledger_source_party_record_detail_service_v1(
  p_ledger_id uuid,
  p_source_party_record_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
  select jsonb_build_object(
    'contractVersion','ledger_source_party_record_detail_v1',
    'ledgerId',r.ledger_id,
    'sourcePartyRecord',jsonb_build_object(
      'sourcePartyRecordId',r.id,
      'sourceConnectionId',r.source_connection_id,
      'providerKey',c.provider_key,
      'providerRecordType',r.provider_record_type,
      'providerRecordId',r.provider_record_id,
      'displayName',r.display_name,
      'sourceRecordState',r.source_record_state,
      'sourcePayload',r.source_payload,
      'payloadHash',r.payload_hash,
      'observedAt',r.observed_at,
      'sourceUpdatedAt',r.source_updated_at,
      'metadata',r.metadata
    ),
    'currentResolution',case
      when x.id is null then null
      else jsonb_build_object(
        'resolutionId',x.id,
        'canonicalEntityId',x.canonical_entity_id,
        'resolutionMethod',x.resolution_method,
        'confidence',x.confidence,
        'resolverVersion',x.resolver_version,
        'resolutionBasis',x.resolution_basis,
        'establishedAt',x.established_at,
        'canonicalEntity',jsonb_strip_nulls(jsonb_build_object(
          'entityId',e.id,
          'name',e.name,
          'entityType',e.entity_type,
          'city',e.city,
          'state',e.state
        ))
      )
    end
  )
  from atlas.ledger_source_party_records r
  join atlas.ledger_source_connections c
    on c.id=r.source_connection_id
   and c.ledger_id=r.ledger_id
  left join atlas.ledger_source_party_resolutions x
    on x.source_party_record_id=r.id
   and x.ledger_id=r.ledger_id
   and x.is_current
  left join local_intel.entities e
    on e.id=x.canonical_entity_id
  where r.id=p_source_party_record_id
    and r.ledger_id=p_ledger_id;
$function$;

revoke all on function atlas.upsert_ledger_source_connection_service_v1(
  uuid,text,text,text,jsonb,jsonb,uuid
) from public,anon,authenticated;
grant execute on function atlas.upsert_ledger_source_connection_service_v1(
  uuid,text,text,text,jsonb,jsonb,uuid
) to service_role;

revoke all on function atlas.upsert_ledger_source_party_record_service_v1(
  uuid,uuid,text,text,text,jsonb,text,timestamptz,timestamptz,jsonb
) from public,anon,authenticated;
grant execute on function atlas.upsert_ledger_source_party_record_service_v1(
  uuid,uuid,text,text,text,jsonb,text,timestamptz,timestamptz,jsonb
) to service_role;

revoke all on function atlas.resolve_ledger_source_party_record_service_v1(
  uuid,uuid,uuid,text,numeric,text,jsonb,uuid,jsonb
) from public,anon,authenticated;
grant execute on function atlas.resolve_ledger_source_party_record_service_v1(
  uuid,uuid,uuid,text,numeric,text,jsonb,uuid,jsonb
) to service_role;

revoke all on function atlas.ledger_source_party_record_detail_service_v1(uuid,uuid)
  from public,anon,authenticated;
grant execute on function atlas.ledger_source_party_record_detail_service_v1(uuid,uuid)
  to service_role;
