-- Atlas Sealed Reality Phase A v1
-- Shared handles + explicit domain authority adapters.
-- No operation execution cutover; no shared warrant/receipt/event tables yet.

create table if not exists atlas.sealed_reality_domain_adapters (
  domain_key text primary key,
  adapter_key text not null unique,
  adapter_version integer not null default 1,
  adapter_state text not null default 'active',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sealed_reality_domain_adapters_domain_key_v1
    check (domain_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint sealed_reality_domain_adapters_adapter_key_v1
    check (adapter_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint sealed_reality_domain_adapters_version_v1
    check (adapter_version >= 1),
  constraint sealed_reality_domain_adapters_state_v1
    check (adapter_state in ('active','retired')),
  constraint sealed_reality_domain_adapters_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

insert into atlas.sealed_reality_domain_adapters(
  domain_key,adapter_key,adapter_version,adapter_state,metadata
)
values
(
  'restricted_personnel_record',
  'restricted_personnel_record_v1',
  1,
  'active',
  '{"proofDomain":"restricted_personnel","sharedKernelPhase":"A"}'::jsonb
),
(
  'sealed_treasury_endpoint',
  'sealed_treasury_endpoint_v1',
  1,
  'active',
  '{"proofDomain":"sealed_treasury","sharedKernelPhase":"A"}'::jsonb
)
on conflict (domain_key) do update
set adapter_key=excluded.adapter_key,
    adapter_version=excluded.adapter_version,
    adapter_state='active',
    metadata=atlas.sealed_reality_domain_adapters.metadata || excluded.metadata,
    updated_at=now();

create table if not exists atlas.sealed_reality_handles (
  id uuid primary key default gen_random_uuid(),
  domain_key text not null
    references atlas.sealed_reality_domain_adapters(domain_key) on delete restrict,
  domain_object_id uuid not null,
  handle_state text not null default 'active',
  registered_by_principal_id uuid not null
    references atlas.principals(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(domain_key,domain_object_id),
  constraint sealed_reality_handles_state_v1
    check (handle_state in ('active','retired')),
  constraint sealed_reality_handles_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

comment on table atlas.sealed_reality_handles is
  'Stable cross-domain handle saying a domain-owned object participates in Sealed Reality execution. It contains no protected plaintext and does not itself establish standing or operation authority.';

alter table atlas.sealed_reality_domain_adapters enable row level security;
alter table atlas.sealed_reality_handles enable row level security;

revoke all on table atlas.sealed_reality_domain_adapters
  from public,anon,authenticated;
revoke all on table atlas.sealed_reality_handles
  from public,anon,authenticated,service_role;

grant select on table atlas.sealed_reality_domain_adapters to service_role;

create or replace function atlas.set_sealed_reality_phase_a_updated_at_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','atlas'
as $function$
begin
  new.updated_at=now();
  return new;
end
$function$;

drop trigger if exists sealed_reality_domain_adapters_updated_at_v1
  on atlas.sealed_reality_domain_adapters;
create trigger sealed_reality_domain_adapters_updated_at_v1
before update on atlas.sealed_reality_domain_adapters
for each row execute function atlas.set_sealed_reality_phase_a_updated_at_v1();

drop trigger if exists sealed_reality_handles_updated_at_v1
  on atlas.sealed_reality_handles;
create trigger sealed_reality_handles_updated_at_v1
before update on atlas.sealed_reality_handles
for each row execute function atlas.set_sealed_reality_phase_a_updated_at_v1();

create or replace function atlas.resolve_restricted_personnel_record_sealed_authority_internal_v1(
  p_domain_object_id uuid,
  p_principal_id uuid,
  p_operation_key text,
  p_purpose_key text,
  p_context jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_record atlas.restricted_vault_records%rowtype;
  v_operation text:=lower(btrim(coalesce(p_operation_key,'')));
  v_purpose text:=lower(btrim(coalesce(p_purpose_key,'')));
  v_authorized boolean:=false;
begin
  if jsonb_typeof(coalesce(p_context,'{}'::jsonb))<>'object' then
    raise exception 'Sealed Reality authority context must be a JSON object.'
      using errcode='22023';
  end if;

  select * into v_record
  from atlas.restricted_vault_records r
  where r.id=p_domain_object_id
    and r.record_state='current';

  if v_record.id is null then
    return jsonb_build_object(
      'authorized',false,
      'authorityVersion','restricted_personnel_record_v1',
      'denialReason','current_personnel_record_not_found'
    );
  end if;

  if v_purpose<>v_record.purpose_key then
    return jsonb_build_object(
      'authorized',false,
      'authorityVersion','restricted_personnel_record_v1',
      'denialReason','purpose_mismatch'
    );
  end if;

  if v_operation='reveal' then
    v_authorized:=atlas.principal_has_restricted_vault_capability_v1(
      p_principal_id,
      v_record.vault_id,
      'vault_record_read',
      v_record.record_class_key,
      v_record.purpose_key
    );

    if not v_authorized then
      return jsonb_build_object(
        'authorized',false,
        'authorityVersion','restricted_personnel_record_v1',
        'denialReason','vault_record_read_required'
      );
    end if;

    return jsonb_build_object(
      'authorized',true,
      'authorityVersion','restricted_personnel_record_v1',
      'authorityBasis',jsonb_build_object(
        'vaultId',v_record.vault_id,
        'recordClassKey',v_record.record_class_key,
        'purposeKey',v_record.purpose_key,
        'requiredCapability','vault_record_read'
      ),
      'requiresCarrier',true,
      'resultPolicy','ephemeral_reveal',
      'revealsPlaintext',true,
      'carrier',jsonb_build_object(
        'carrierKey','restricted_vault_envelope_v1',
        'carrierLocator','atlas://restricted-personnel-record/'||v_record.id::text,
        'carrierVersion','1'
      ),
      'warrantTtlSeconds',120
    );
  end if;

  return jsonb_build_object(
    'authorized',false,
    'authorityVersion','restricted_personnel_record_v1',
    'denialReason','unsupported_operation'
  );
end
$function$;

revoke all on function atlas.resolve_restricted_personnel_record_sealed_authority_internal_v1(
  uuid,uuid,text,text,jsonb
) from public,anon,authenticated,service_role;

create or replace function atlas.resolve_sealed_treasury_endpoint_sealed_authority_internal_v1(
  p_domain_object_id uuid,
  p_principal_id uuid,
  p_operation_key text,
  p_purpose_key text,
  p_context jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_endpoint atlas.sealed_treasury_endpoints%rowtype;
  v_operation atlas.sealed_treasury_operations%rowtype;
  v_operation_key text:=lower(btrim(coalesce(p_operation_key,'')));
  v_purpose text:=lower(btrim(coalesce(p_purpose_key,'')));
  v_authorized boolean:=false;
begin
  if jsonb_typeof(coalesce(p_context,'{}'::jsonb))<>'object' then
    raise exception 'Sealed Reality authority context must be a JSON object.'
      using errcode='22023';
  end if;

  select * into v_endpoint
  from atlas.sealed_treasury_endpoints e
  where e.id=p_domain_object_id
    and e.endpoint_state='active';

  if v_endpoint.id is null then
    return jsonb_build_object(
      'authorized',false,
      'authorityVersion','sealed_treasury_endpoint_v1',
      'denialReason','active_treasury_endpoint_not_found'
    );
  end if;

  select * into v_operation
  from atlas.sealed_treasury_operations o
  where o.operation_key=v_operation_key
    and o.operation_state='active';

  if v_operation.operation_key is null then
    return jsonb_build_object(
      'authorized',false,
      'authorityVersion','sealed_treasury_endpoint_v1',
      'denialReason','unsupported_operation'
    );
  end if;

  v_authorized:=atlas.principal_has_sealed_treasury_operation_v1(
    p_principal_id,
    v_endpoint.id,
    v_operation.operation_key,
    v_purpose
  );

  if not v_authorized then
    return jsonb_build_object(
      'authorized',false,
      'authorityVersion','sealed_treasury_endpoint_v1',
      'denialReason','operation_authority_required'
    );
  end if;

  return jsonb_build_object(
    'authorized',true,
    'authorityVersion','sealed_treasury_endpoint_v1',
    'authorityBasis',jsonb_build_object(
      'endpointId',v_endpoint.id,
      'ledgerId',v_endpoint.ledger_id,
      'operationKey',v_operation.operation_key,
      'purposeKey',v_purpose
    ),
    'requiresCarrier',v_operation.requires_carrier,
    'resultPolicy',v_operation.result_policy,
    'revealsPlaintext',v_operation.reveals_plaintext,
    'carrier',
      case
        when v_operation.requires_carrier then
          jsonb_build_object(
            'carrierKey',v_endpoint.carrier_key,
            'carrierLocator',v_endpoint.carrier_locator,
            'carrierVersion',v_endpoint.carrier_version
          )
        else null
      end,
    'warrantTtlSeconds',v_operation.default_warrant_ttl_seconds
  );
end
$function$;

revoke all on function atlas.resolve_sealed_treasury_endpoint_sealed_authority_internal_v1(
  uuid,uuid,text,text,jsonb
) from public,anon,authenticated,service_role;

create or replace function atlas.register_sealed_reality_handle_service_v1(
  p_domain_key text,
  p_domain_object_id uuid,
  p_registered_by_principal_id uuid,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_domain text:=lower(btrim(coalesce(p_domain_key,'')));
  v_handle atlas.sealed_reality_handles%rowtype;
  v_vault_id uuid;
  v_allowed boolean:=false;
begin
  if jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then
    raise exception 'Sealed Reality handle metadata must be a JSON object.'
      using errcode='22023';
  end if;

  if not exists(
    select 1
    from atlas.sealed_reality_domain_adapters a
    where a.domain_key=v_domain
      and a.adapter_state='active'
  ) then
    raise exception 'Active Sealed Reality domain adapter not found.'
      using errcode='P0002';
  end if;

  select * into v_handle
  from atlas.sealed_reality_handles h
  where h.domain_key=v_domain
    and h.domain_object_id=p_domain_object_id;

  if v_handle.id is not null then
    if v_handle.handle_state<>'active' then
      raise exception 'Sealed Reality handle is retired.'
        using errcode='55000';
    end if;

    return jsonb_build_object(
      'contractVersion','sealed_reality_handle_v1',
      'idempotentReplay',true,
      'handleId',v_handle.id,
      'domainKey',v_handle.domain_key,
      'domainObjectId',v_handle.domain_object_id,
      'handleState',v_handle.handle_state
    );
  end if;

  if v_domain='restricted_personnel_record' then
    select r.vault_id into v_vault_id
    from atlas.restricted_vault_records r
    where r.id=p_domain_object_id
      and r.record_state='current';

    if v_vault_id is null then
      raise exception 'Current restricted personnel record not found.'
        using errcode='P0002';
    end if;

    v_allowed:=atlas.principal_has_restricted_vault_capability_v1(
      p_registered_by_principal_id,
      v_vault_id,
      'vault_entitlement_admin',
      null,
      null
    );

  elsif v_domain='sealed_treasury_endpoint' then
    if not exists(
      select 1
      from atlas.sealed_treasury_endpoints e
      where e.id=p_domain_object_id
        and e.endpoint_state='active'
    ) then
      raise exception 'Active sealed treasury endpoint not found.'
        using errcode='P0002';
    end if;

    v_allowed:=atlas.principal_has_sealed_treasury_operation_v1(
      p_registered_by_principal_id,
      p_domain_object_id,
      'delegate_operation',
      null
    );

  else
    raise exception 'Sealed Reality domain adapter is not supported by dispatcher.'
      using errcode='0A000';
  end if;

  if not v_allowed then
    raise exception 'Principal lacks domain-governance authority to register this Sealed Reality handle.'
      using errcode='42501';
  end if;

  insert into atlas.sealed_reality_handles(
    domain_key,domain_object_id,handle_state,registered_by_principal_id,metadata
  )
  values(
    v_domain,p_domain_object_id,'active',
    p_registered_by_principal_id,coalesce(p_metadata,'{}'::jsonb)
  )
  returning * into v_handle;

  return jsonb_build_object(
    'contractVersion','sealed_reality_handle_v1',
    'idempotentReplay',false,
    'handleId',v_handle.id,
    'domainKey',v_handle.domain_key,
    'domainObjectId',v_handle.domain_object_id,
    'handleState',v_handle.handle_state
  );
end
$function$;

create or replace function atlas.resolve_sealed_reality_operation_authority_service_v1(
  p_handle_id uuid,
  p_principal_id uuid,
  p_operation_key text,
  p_purpose_key text,
  p_context jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_handle atlas.sealed_reality_handles%rowtype;
  v_adapter atlas.sealed_reality_domain_adapters%rowtype;
  v_decision jsonb;
  v_operation text:=lower(btrim(coalesce(p_operation_key,'')));
  v_purpose text:=lower(btrim(coalesce(p_purpose_key,'')));
begin
  if v_operation !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
     or v_purpose !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$' then
    raise exception 'Operation and purpose keys must be normalized.'
      using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_context,'{}'::jsonb))<>'object' then
    raise exception 'Sealed Reality authority context must be a JSON object.'
      using errcode='22023';
  end if;

  select * into v_handle
  from atlas.sealed_reality_handles h
  where h.id=p_handle_id
    and h.handle_state='active';

  if v_handle.id is null then
    raise exception 'Active Sealed Reality handle not found.'
      using errcode='P0002';
  end if;

  select * into v_adapter
  from atlas.sealed_reality_domain_adapters a
  where a.domain_key=v_handle.domain_key
    and a.adapter_state='active';

  if v_adapter.domain_key is null then
    raise exception 'Active Sealed Reality adapter not found.'
      using errcode='P0002';
  end if;

  -- Deliberately explicit dispatcher: no metadata-driven dynamic SQL.
  if v_handle.domain_key='restricted_personnel_record'
     and v_adapter.adapter_key='restricted_personnel_record_v1' then
    v_decision:=atlas.resolve_restricted_personnel_record_sealed_authority_internal_v1(
      v_handle.domain_object_id,
      p_principal_id,
      v_operation,
      v_purpose,
      coalesce(p_context,'{}'::jsonb)
    );

  elsif v_handle.domain_key='sealed_treasury_endpoint'
     and v_adapter.adapter_key='sealed_treasury_endpoint_v1' then
    v_decision:=atlas.resolve_sealed_treasury_endpoint_sealed_authority_internal_v1(
      v_handle.domain_object_id,
      p_principal_id,
      v_operation,
      v_purpose,
      coalesce(p_context,'{}'::jsonb)
    );

  else
    raise exception 'Sealed Reality adapter is registered but not implemented by dispatcher.'
      using errcode='0A000';
  end if;

  return jsonb_build_object(
    'contractVersion','sealed_reality_authority_resolution_v1',
    'handleId',v_handle.id,
    'domainKey',v_handle.domain_key,
    'domainObjectId',v_handle.domain_object_id,
    'adapterKey',v_adapter.adapter_key,
    'adapterVersion',v_adapter.adapter_version,
    'operationKey',v_operation,
    'purposeKey',v_purpose,
    'decision',v_decision
  );
end
$function$;

revoke all on function atlas.register_sealed_reality_handle_service_v1(
  text,uuid,uuid,jsonb
) from public,anon,authenticated;
grant execute on function atlas.register_sealed_reality_handle_service_v1(
  text,uuid,uuid,jsonb
) to service_role;

revoke all on function atlas.resolve_sealed_reality_operation_authority_service_v1(
  uuid,uuid,text,text,jsonb
) from public,anon,authenticated;
grant execute on function atlas.resolve_sealed_reality_operation_authority_service_v1(
  uuid,uuid,text,text,jsonb
) to service_role;
