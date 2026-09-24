-- Atlas Sealed Reality Shared Kernel Phase B v1.
-- Shared one-time operation warrant, bounded receipt, carrier completion,
-- and append-only audit lineage.
-- Domain authority remains owned by Phase A adapters. No domain cutover.

create table if not exists atlas.sealed_reality_operation_warrants (
  id uuid primary key default gen_random_uuid(),
  sealed_reality_handle_id uuid not null
    references atlas.sealed_reality_handles(id) on delete restrict,
  principal_id uuid not null
    references atlas.principals(id) on delete restrict,
  domain_key text not null
    references atlas.sealed_reality_domain_adapters(domain_key) on delete restrict,
  adapter_key text not null,
  adapter_version integer not null,
  operation_key text not null,
  purpose_key text not null,
  authority_version text not null,
  authority_basis jsonb not null default '{}'::jsonb,
  result_policy text not null,
  reveals_plaintext boolean not null default false,
  carrier_key text not null,
  carrier_locator text not null,
  carrier_version text,
  warrant_token_hash bytea not null unique,
  warrant_state text not null default 'issued',
  issued_at timestamptz not null default now(),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  revoked_at timestamptz,
  reason_text text not null,
  request_context jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint sealed_reality_operation_warrants_adapter_key_v1
    check (adapter_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint sealed_reality_operation_warrants_adapter_version_v1
    check (adapter_version >= 1),
  constraint sealed_reality_operation_warrants_operation_v1
    check (operation_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint sealed_reality_operation_warrants_purpose_v1
    check (purpose_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint sealed_reality_operation_warrants_authority_version_v1
    check (btrim(authority_version) <> ''),
  constraint sealed_reality_operation_warrants_authority_basis_v1
    check (jsonb_typeof(authority_basis)='object'),
  constraint sealed_reality_operation_warrants_result_policy_v1
    check (result_policy in ('none','boolean','string','scalar','receipt','ephemeral_reveal')),
  constraint sealed_reality_operation_warrants_reveal_v1
    check (
      (reveals_plaintext and result_policy='ephemeral_reveal')
      or
      (not reveals_plaintext and result_policy<>'ephemeral_reveal')
    ),
  constraint sealed_reality_operation_warrants_carrier_key_v1
    check (carrier_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint sealed_reality_operation_warrants_carrier_locator_v1
    check (btrim(carrier_locator) <> ''),
  constraint sealed_reality_operation_warrants_state_v1
    check (warrant_state in ('issued','consumed','expired','revoked')),
  constraint sealed_reality_operation_warrants_expiry_v1
    check (expires_at > issued_at and expires_at <= issued_at + interval '15 minutes'),
  constraint sealed_reality_operation_warrants_shape_v1
    check (
      (warrant_state='issued' and consumed_at is null and revoked_at is null)
      or
      (warrant_state='consumed' and consumed_at is not null and revoked_at is null)
      or
      (warrant_state='expired' and consumed_at is null and revoked_at is null)
      or
      (warrant_state='revoked' and consumed_at is null and revoked_at is not null)
    ),
  constraint sealed_reality_operation_warrants_reason_v1
    check (btrim(reason_text) <> ''),
  constraint sealed_reality_operation_warrants_context_v1
    check (jsonb_typeof(request_context)='object')
);

create index if not exists sealed_reality_operation_warrants_lookup_idx_v1
  on atlas.sealed_reality_operation_warrants(
    sealed_reality_handle_id,principal_id,operation_key,warrant_state,expires_at
  );

comment on table atlas.sealed_reality_operation_warrants is
  'Cross-domain one-time execution warrant. It snapshots a domain-owned authority decision and carries it to one replaceable carrier without becoming the source of authority. Only a hash of the bearer token is stored.';

create table if not exists atlas.sealed_reality_operation_receipts (
  id uuid primary key default gen_random_uuid(),
  warrant_id uuid not null unique
    references atlas.sealed_reality_operation_warrants(id) on delete restrict,
  outcome text not null,
  result_policy text not null,
  safe_result jsonb,
  carrier_key text not null,
  carrier_receipt_ref text,
  completed_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint sealed_reality_operation_receipts_outcome_v1
    check (outcome in ('completed','failed')),
  constraint sealed_reality_operation_receipts_policy_v1
    check (result_policy in ('none','boolean','string','scalar','receipt','ephemeral_reveal')),
  constraint sealed_reality_operation_receipts_result_size_v1
    check (safe_result is null or octet_length(safe_result::text)<=4096),
  constraint sealed_reality_operation_receipts_carrier_v1
    check (carrier_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint sealed_reality_operation_receipts_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

comment on table atlas.sealed_reality_operation_receipts is
  'Bounded durable result of one Sealed Reality carrier execution. A receipt must not become a second copy of the protected fact.';

create table if not exists atlas.sealed_reality_operation_events (
  id uuid primary key default gen_random_uuid(),
  sealed_reality_handle_id uuid not null
    references atlas.sealed_reality_handles(id) on delete restrict,
  principal_id uuid references atlas.principals(id) on delete set null,
  domain_key text not null,
  event_key text not null,
  outcome text not null,
  operation_key text,
  purpose_key text,
  warrant_id uuid
    references atlas.sealed_reality_operation_warrants(id) on delete set null,
  receipt_id uuid
    references atlas.sealed_reality_operation_receipts(id) on delete set null,
  reason_text text,
  context jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint sealed_reality_operation_events_domain_v1
    check (domain_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint sealed_reality_operation_events_event_v1
    check (event_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint sealed_reality_operation_events_outcome_v1
    check (outcome in ('allowed','denied','completed','failed','expired','revoked')),
  constraint sealed_reality_operation_events_operation_v1
    check (operation_key is null or operation_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint sealed_reality_operation_events_purpose_v1
    check (purpose_key is null or purpose_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint sealed_reality_operation_events_context_v1
    check (jsonb_typeof(context)='object')
);

create index if not exists sealed_reality_operation_events_handle_time_idx_v1
  on atlas.sealed_reality_operation_events(sealed_reality_handle_id,occurred_at desc);

create index if not exists sealed_reality_operation_events_principal_time_idx_v1
  on atlas.sealed_reality_operation_events(principal_id,occurred_at desc);

comment on table atlas.sealed_reality_operation_events is
  'Append-only cross-domain audit lineage for Sealed Reality authority resolution, warrant issuance, carrier completion, failure, expiry, and denial. Protected plaintext is forbidden from event context.';

alter table atlas.sealed_reality_operation_warrants enable row level security;
alter table atlas.sealed_reality_operation_receipts enable row level security;
alter table atlas.sealed_reality_operation_events enable row level security;

revoke all on table atlas.sealed_reality_operation_warrants
  from public,anon,authenticated,service_role;
revoke all on table atlas.sealed_reality_operation_receipts
  from public,anon,authenticated,service_role;
revoke all on table atlas.sealed_reality_operation_events
  from public,anon,authenticated,service_role;

create or replace function atlas.prevent_sealed_reality_immutable_mutation_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','atlas'
as $function$
begin
  raise exception 'Sealed Reality receipt/event rows are append-only.'
    using errcode='42501';
end
$function$;

drop trigger if exists sealed_reality_receipts_append_only_v1
  on atlas.sealed_reality_operation_receipts;
create trigger sealed_reality_receipts_append_only_v1
before update or delete on atlas.sealed_reality_operation_receipts
for each row execute function atlas.prevent_sealed_reality_immutable_mutation_v1();

drop trigger if exists sealed_reality_events_append_only_v1
  on atlas.sealed_reality_operation_events;
create trigger sealed_reality_events_append_only_v1
before update or delete on atlas.sealed_reality_operation_events
for each row execute function atlas.prevent_sealed_reality_immutable_mutation_v1();

create or replace function atlas.write_sealed_reality_operation_event_internal_v1(
  p_handle_id uuid,
  p_principal_id uuid,
  p_domain_key text,
  p_event_key text,
  p_outcome text,
  p_operation_key text default null,
  p_purpose_key text default null,
  p_warrant_id uuid default null,
  p_receipt_id uuid default null,
  p_reason_text text default null,
  p_context jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_id uuid;
begin
  if jsonb_typeof(coalesce(p_context,'{}'::jsonb))<>'object' then
    raise exception 'Sealed Reality event context must be a JSON object.'
      using errcode='22023';
  end if;

  insert into atlas.sealed_reality_operation_events(
    sealed_reality_handle_id,principal_id,domain_key,event_key,outcome,
    operation_key,purpose_key,warrant_id,receipt_id,reason_text,context
  )
  values(
    p_handle_id,p_principal_id,lower(btrim(p_domain_key)),
    lower(btrim(p_event_key)),lower(btrim(p_outcome)),
    case when p_operation_key is null then null else lower(btrim(p_operation_key)) end,
    case when p_purpose_key is null then null else lower(btrim(p_purpose_key)) end,
    p_warrant_id,p_receipt_id,nullif(btrim(p_reason_text),''),
    coalesce(p_context,'{}'::jsonb)
  )
  returning id into v_id;

  return v_id;
end
$function$;

revoke all on function atlas.write_sealed_reality_operation_event_internal_v1(
  uuid,uuid,text,text,text,text,text,uuid,uuid,text,jsonb
) from public,anon,authenticated,service_role;

create or replace function atlas.request_sealed_reality_operation_service_v1(
  p_handle_id uuid,
  p_principal_id uuid,
  p_operation_key text,
  p_purpose_key text,
  p_reason text,
  p_context jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','extensions'
as $function$
declare
  v_operation text:=lower(btrim(coalesce(p_operation_key,'')));
  v_purpose text:=lower(btrim(coalesce(p_purpose_key,'')));
  v_resolution jsonb;
  v_decision jsonb;
  v_domain text;
  v_adapter_key text;
  v_adapter_version integer;
  v_authorized boolean;
  v_requires_carrier boolean;
  v_result_policy text;
  v_reveals_plaintext boolean;
  v_authority_version text;
  v_authority_basis jsonb;
  v_carrier jsonb;
  v_carrier_key text;
  v_carrier_locator text;
  v_carrier_version text;
  v_ttl integer;
  v_token text;
  v_token_hash bytea;
  v_warrant atlas.sealed_reality_operation_warrants%rowtype;
begin
  if v_operation !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
     or v_purpose !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
     or btrim(coalesce(p_reason,''))='' then
    raise exception 'Handle, normalized operation/purpose, and reason are required.'
      using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_context,'{}'::jsonb))<>'object' then
    raise exception 'Sealed Reality request context must be a JSON object.'
      using errcode='22023';
  end if;

  v_resolution:=atlas.resolve_sealed_reality_operation_authority_service_v1(
    p_handle_id,p_principal_id,v_operation,v_purpose,coalesce(p_context,'{}'::jsonb)
  );

  v_domain:=v_resolution->>'domainKey';
  v_adapter_key:=v_resolution->>'adapterKey';
  v_adapter_version:=(v_resolution->>'adapterVersion')::integer;
  v_decision:=v_resolution->'decision';
  v_authorized:=coalesce((v_decision->>'authorized')::boolean,false);

  if not v_authorized then
    perform atlas.write_sealed_reality_operation_event_internal_v1(
      p_handle_id,p_principal_id,v_domain,'operation_request','denied',
      v_operation,v_purpose,null,null,p_reason,
      jsonb_build_object(
        'adapterKey',v_adapter_key,
        'adapterVersion',v_adapter_version,
        'denialReason',v_decision->>'denialReason'
      )
    );

    return jsonb_build_object(
      'contractVersion','sealed_reality_operation_request_v1',
      'authorized',false,
      'handleId',p_handle_id,
      'domainKey',v_domain,
      'operationKey',v_operation,
      'purposeKey',v_purpose,
      'reason',coalesce(v_decision->>'denialReason','domain_authority_denied')
    );
  end if;

  v_requires_carrier:=coalesce((v_decision->>'requiresCarrier')::boolean,false);
  v_result_policy:=v_decision->>'resultPolicy';
  v_reveals_plaintext:=coalesce((v_decision->>'revealsPlaintext')::boolean,false);
  v_authority_version:=v_decision->>'authorityVersion';
  v_authority_basis:=coalesce(v_decision->'authorityBasis','{}'::jsonb);

  if v_result_policy not in ('none','boolean','string','scalar','receipt','ephemeral_reveal')
     or btrim(coalesce(v_authority_version,''))=''
     or jsonb_typeof(v_authority_basis)<>'object'
     or (v_reveals_plaintext and v_result_policy<>'ephemeral_reveal')
     or (not v_reveals_plaintext and v_result_policy='ephemeral_reveal') then
    raise exception 'Domain adapter returned an invalid Sealed Reality decision envelope.'
      using errcode='22023';
  end if;

  if not v_requires_carrier then
    perform atlas.write_sealed_reality_operation_event_internal_v1(
      p_handle_id,p_principal_id,v_domain,'authority_resolved','allowed',
      v_operation,v_purpose,null,null,p_reason,
      jsonb_build_object(
        'adapterKey',v_adapter_key,
        'adapterVersion',v_adapter_version,
        'authorityVersion',v_authority_version,
        'resultPolicy',v_result_policy
      )
    );

    return jsonb_build_object(
      'contractVersion','sealed_reality_operation_request_v1',
      'authorized',true,
      'handleId',p_handle_id,
      'domainKey',v_domain,
      'operationKey',v_operation,
      'purposeKey',v_purpose,
      'requiresCarrier',false,
      'executionState','domain_owned',
      'resultPolicy',v_result_policy,
      'revealsPlaintext',v_reveals_plaintext,
      'authorityVersion',v_authority_version
    );
  end if;

  v_carrier:=v_decision->'carrier';
  v_carrier_key:=lower(btrim(coalesce(v_carrier->>'carrierKey','')));
  v_carrier_locator:=btrim(coalesce(v_carrier->>'carrierLocator',''));
  v_carrier_version:=nullif(btrim(v_carrier->>'carrierVersion'),'');
  v_ttl:=(v_decision->>'warrantTtlSeconds')::integer;

  if jsonb_typeof(v_carrier)<>'object'
     or v_carrier_key !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
     or v_carrier_locator=''
     or v_ttl<30
     or v_ttl>900 then
    raise exception 'Domain adapter returned an invalid carrier/warrant contract.'
      using errcode='22023';
  end if;

  v_token:=encode(extensions.gen_random_bytes(32),'hex');
  v_token_hash:=extensions.digest(v_token,'sha256');

  insert into atlas.sealed_reality_operation_warrants(
    sealed_reality_handle_id,principal_id,domain_key,adapter_key,adapter_version,
    operation_key,purpose_key,authority_version,authority_basis,
    result_policy,reveals_plaintext,carrier_key,carrier_locator,carrier_version,
    warrant_token_hash,warrant_state,issued_at,expires_at,reason_text,request_context
  )
  values(
    p_handle_id,p_principal_id,v_domain,v_adapter_key,v_adapter_version,
    v_operation,v_purpose,v_authority_version,v_authority_basis,
    v_result_policy,v_reveals_plaintext,v_carrier_key,v_carrier_locator,v_carrier_version,
    v_token_hash,'issued',now(),now()+make_interval(secs=>v_ttl),
    btrim(p_reason),coalesce(p_context,'{}'::jsonb)
  )
  returning * into v_warrant;

  perform atlas.write_sealed_reality_operation_event_internal_v1(
    p_handle_id,p_principal_id,v_domain,'operation_request','allowed',
    v_operation,v_purpose,v_warrant.id,null,p_reason,
    jsonb_build_object(
      'adapterKey',v_adapter_key,
      'adapterVersion',v_adapter_version,
      'authorityVersion',v_authority_version,
      'resultPolicy',v_result_policy,
      'revealsPlaintext',v_reveals_plaintext
    )
  );

  perform atlas.write_sealed_reality_operation_event_internal_v1(
    p_handle_id,p_principal_id,v_domain,'warrant_issued','completed',
    v_operation,v_purpose,v_warrant.id,null,p_reason,
    jsonb_build_object(
      'carrierKey',v_carrier_key,
      'expiresAt',v_warrant.expires_at
    )
  );

  return jsonb_build_object(
    'contractVersion','sealed_reality_operation_request_v1',
    'authorized',true,
    'handleId',p_handle_id,
    'domainKey',v_domain,
    'operationKey',v_operation,
    'purposeKey',v_purpose,
    'requiresCarrier',true,
    'warrantId',v_warrant.id,
    'warrantToken',v_token,
    'expiresAt',v_warrant.expires_at,
    'authorityVersion',v_authority_version,
    'resultPolicy',v_result_policy,
    'revealsPlaintext',v_reveals_plaintext,
    'carrier',jsonb_build_object(
      'carrierKey',v_carrier_key,
      'carrierLocator',v_carrier_locator,
      'carrierVersion',v_carrier_version
    )
  );
end
$function$;

create or replace function atlas.complete_sealed_reality_operation_service_v1(
  p_warrant_token text,
  p_outcome text,
  p_carrier_key text,
  p_safe_result jsonb default null,
  p_carrier_receipt_ref text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','extensions'
as $function$
declare
  v_token text:=lower(btrim(coalesce(p_warrant_token,'')));
  v_hash bytea;
  v_warrant atlas.sealed_reality_operation_warrants%rowtype;
  v_outcome text:=lower(btrim(coalesce(p_outcome,'')));
  v_carrier text:=lower(btrim(coalesce(p_carrier_key,'')));
  v_receipt atlas.sealed_reality_operation_receipts%rowtype;
  v_type text;
begin
  if v_token !~ '^[0-9a-f]{64}$' then
    raise exception 'Sealed Reality warrant token is invalid.'
      using errcode='22023';
  end if;

  if v_carrier !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$' then
    raise exception 'Carrier key is invalid.' using errcode='22023';
  end if;

  if v_outcome not in ('completed','failed') then
    raise exception 'Carrier outcome must be completed or failed.'
      using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then
    raise exception 'Carrier completion metadata must be a JSON object.'
      using errcode='22023';
  end if;

  if p_safe_result is not null and octet_length(p_safe_result::text)>4096 then
    raise exception 'Carrier safe result exceeds allowed size.'
      using errcode='22023';
  end if;

  v_hash:=extensions.digest(v_token,'sha256');

  select * into v_warrant
  from atlas.sealed_reality_operation_warrants w
  where w.warrant_token_hash=v_hash
  for update;

  if v_warrant.id is null then
    raise exception 'Sealed Reality operation warrant not found.'
      using errcode='P0002';
  end if;

  if v_warrant.warrant_state<>'issued' then
    raise exception 'Sealed Reality operation warrant is no longer usable.'
      using errcode='22023';
  end if;

  if v_warrant.expires_at<=now() then
    update atlas.sealed_reality_operation_warrants
    set warrant_state='expired'
    where id=v_warrant.id;

    perform atlas.write_sealed_reality_operation_event_internal_v1(
      v_warrant.sealed_reality_handle_id,v_warrant.principal_id,
      v_warrant.domain_key,'warrant_expired','expired',
      v_warrant.operation_key,v_warrant.purpose_key,v_warrant.id,null,
      'carrier completion arrived after warrant expiry',
      jsonb_build_object('carrierKey',v_carrier)
    );

    return jsonb_build_object(
      'contractVersion','sealed_reality_operation_completion_v1',
      'completed',false,
      'warrantId',v_warrant.id,
      'reason','warrant_expired'
    );
  end if;

  if v_carrier<>v_warrant.carrier_key then
    perform atlas.write_sealed_reality_operation_event_internal_v1(
      v_warrant.sealed_reality_handle_id,v_warrant.principal_id,
      v_warrant.domain_key,'carrier_completion','denied',
      v_warrant.operation_key,v_warrant.purpose_key,v_warrant.id,null,
      'carrier identity does not match issued warrant',
      jsonb_build_object(
        'expectedCarrierKey',v_warrant.carrier_key,
        'presentedCarrierKey',v_carrier
      )
    );

    return jsonb_build_object(
      'contractVersion','sealed_reality_operation_completion_v1',
      'completed',false,
      'warrantId',v_warrant.id,
      'reason','carrier_mismatch'
    );
  end if;

  if v_outcome='completed' then
    v_type:=jsonb_typeof(p_safe_result);

    if v_warrant.result_policy='none'
       and p_safe_result is not null then
      raise exception 'This operation permits no durable result.'
        using errcode='22023';

    elsif v_warrant.result_policy='boolean'
       and v_type<>'boolean' then
      raise exception 'This operation may return only a boolean.'
        using errcode='22023';

    elsif v_warrant.result_policy='string'
       and (
         v_type<>'string'
         or length(p_safe_result#>>'{}')>256
       ) then
      raise exception 'This operation may return only a bounded string.'
        using errcode='22023';

    elsif v_warrant.result_policy='scalar'
       and v_type not in ('boolean','string','number','null') then
      raise exception 'This operation may return only a scalar.'
        using errcode='22023');

    elsif v_warrant.result_policy='receipt'
       and v_type<>'object' then
      raise exception 'This operation must return a bounded receipt object.'
        using errcode='22023';

    elsif v_warrant.result_policy='ephemeral_reveal'
       and p_safe_result is distinct from '{"delivered":true}'::jsonb then
      raise exception 'Revealed plaintext must not persist in the canonical receipt.'
        using errcode='22023';
    end if;

  else
    if p_safe_result is not null
       and (
         jsonb_typeof(p_safe_result)<>'object'
         or (p_safe_result-'errorClass')<>'{}'::jsonb
         or jsonb_typeof(p_safe_result->'errorClass')<>'string'
         or length(p_safe_result->>'errorClass')>128
       ) then
      raise exception 'Failed carrier result may contain only bounded errorClass metadata.'
        using errcode='22023';
    end if;
  end if;

  update atlas.sealed_reality_operation_warrants
  set warrant_state='consumed',
      consumed_at=now()
  where id=v_warrant.id;

  insert into atlas.sealed_reality_operation_receipts(
    warrant_id,outcome,result_policy,safe_result,carrier_key,
    carrier_receipt_ref,metadata
  )
  values(
    v_warrant.id,v_outcome,v_warrant.result_policy,p_safe_result,
    v_carrier,nullif(btrim(p_carrier_receipt_ref),''),
    coalesce(p_metadata,'{}'::jsonb)
  )
  returning * into v_receipt;

  perform atlas.write_sealed_reality_operation_event_internal_v1(
    v_warrant.sealed_reality_handle_id,v_warrant.principal_id,
    v_warrant.domain_key,'carrier_completion',
    case when v_outcome='completed' then 'completed' else 'failed' end,
    v_warrant.operation_key,v_warrant.purpose_key,v_warrant.id,v_receipt.id,
    'Sealed Reality carrier completed one-time operation',
    jsonb_build_object(
      'carrierKey',v_carrier,
      'resultPolicy',v_warrant.result_policy
    )
  );

  return jsonb_build_object(
    'contractVersion','sealed_reality_operation_completion_v1',
    'completed',v_outcome='completed',
    'receiptId',v_receipt.id,
    'warrantId',v_warrant.id,
    'handleId',v_warrant.sealed_reality_handle_id,
    'domainKey',v_warrant.domain_key,
    'operationKey',v_warrant.operation_key,
    'purposeKey',v_warrant.purpose_key,
    'resultPolicy',v_warrant.result_policy,
    'safeResult',v_receipt.safe_result,
    'carrierReceiptRef',v_receipt.carrier_receipt_ref
  );
end
$function$;

revoke all on function atlas.request_sealed_reality_operation_service_v1(
  uuid,uuid,text,text,text,jsonb
) from public,anon,authenticated;
grant execute on function atlas.request_sealed_reality_operation_service_v1(
  uuid,uuid,text,text,text,jsonb
) to service_role;

revoke all on function atlas.complete_sealed_reality_operation_service_v1(
  text,text,text,jsonb,text,jsonb
) from public,anon,authenticated;
grant execute on function atlas.complete_sealed_reality_operation_service_v1(
  text,text,text,jsonb,text,jsonb
) to service_role;
