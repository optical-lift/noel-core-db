-- Atlas Sealed Treasury Authority — second-domain proof v1.
-- Institution-governed sensitive financial destination authority.
-- No bank/routing/card plaintext is stored in this kernel.

create table if not exists atlas.sealed_treasury_operations (
  operation_key text primary key,
  title text not null,
  requires_carrier boolean not null default true,
  result_policy text not null,
  reveals_plaintext boolean not null default false,
  default_warrant_ttl_seconds integer,
  operation_state text not null default 'active',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sealed_treasury_operations_key_v1
    check (operation_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint sealed_treasury_operations_result_policy_v1
    check (result_policy in ('none','boolean','string','receipt','ephemeral_reveal')),
  constraint sealed_treasury_operations_ttl_v1
    check (
      (requires_carrier and default_warrant_ttl_seconds between 30 and 900)
      or
      (not requires_carrier and default_warrant_ttl_seconds is null)
    ),
  constraint sealed_treasury_operations_reveal_v1
    check (
      (reveals_plaintext and result_policy='ephemeral_reveal')
      or
      (not reveals_plaintext and result_policy<>'ephemeral_reveal')
    ),
  constraint sealed_treasury_operations_state_v1
    check (operation_state in ('active','retired')),
  constraint sealed_treasury_operations_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

insert into atlas.sealed_treasury_operations(
  operation_key,title,requires_carrier,result_policy,reveals_plaintext,
  default_warrant_ttl_seconds,metadata
)
values
('observe_existence','Observe treasury endpoint existence',false,'none',false,null,'{"class":"knowledge"}'::jsonb),
('verify_destination','Verify treasury destination',true,'boolean',false,300,'{"class":"derived"}'::jsonb),
('compare_destination','Compare candidate treasury destination',true,'boolean',false,300,'{"class":"derived"}'::jsonb),
('submit_payment_destination','Submit treasury destination for an authorized payment purpose',true,'receipt',false,180,'{"class":"action"}'::jsonb),
('reveal_hint','Reveal bounded treasury destination hint',true,'string',false,180,'{"class":"bounded_reveal"}'::jsonb),
('reveal_full','Reveal full treasury destination exceptionally',true,'ephemeral_reveal',true,120,'{"class":"exceptional_reveal"}'::jsonb),
('delegate_operation','Delegate treasury operation authority',false,'none',false,null,'{"class":"governance"}'::jsonb),
('audit_operations','Read treasury operation audit lineage',false,'none',false,null,'{"class":"audit"}'::jsonb)
on conflict (operation_key) do update
set title=excluded.title,
    requires_carrier=excluded.requires_carrier,
    result_policy=excluded.result_policy,
    reveals_plaintext=excluded.reveals_plaintext,
    default_warrant_ttl_seconds=excluded.default_warrant_ttl_seconds,
    operation_state='active',
    metadata=atlas.sealed_treasury_operations.metadata || excluded.metadata,
    updated_at=now();

create table if not exists atlas.sealed_treasury_endpoints (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references atlas.ledgers(id) on delete restrict,
  stable_key text not null,
  title text not null,
  endpoint_kind text not null default 'bank_destination',
  endpoint_state text not null default 'active',
  carrier_key text not null,
  carrier_locator text not null,
  carrier_version text,
  created_by_principal_id uuid not null references atlas.principals(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (ledger_id,stable_key),
  constraint sealed_treasury_endpoints_stable_key_v1
    check (stable_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint sealed_treasury_endpoints_title_v1
    check (btrim(title)<>''),
  constraint sealed_treasury_endpoints_kind_v1
    check (endpoint_kind in ('bank_destination')),
  constraint sealed_treasury_endpoints_state_v1
    check (endpoint_state in ('active','retired')),
  constraint sealed_treasury_endpoints_carrier_key_v1
    check (carrier_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint sealed_treasury_endpoints_carrier_locator_v1
    check (btrim(carrier_locator)<>''),
  constraint sealed_treasury_endpoints_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

comment on table atlas.sealed_treasury_endpoints is
  'Second Sealed Reality proof domain. Records governance and an opaque carrier locator for an institution-governed treasury destination; never stores the bank/routing/card plaintext itself.';

create table if not exists atlas.sealed_treasury_operation_grants (
  id uuid primary key default gen_random_uuid(),
  endpoint_id uuid not null references atlas.sealed_treasury_endpoints(id) on delete restrict,
  principal_id uuid not null references atlas.principals(id) on delete restrict,
  operation_key text not null references atlas.sealed_treasury_operations(operation_key) on delete restrict,
  purpose_scope text[] not null default '{}'::text[],
  grant_state text not null default 'active',
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  granted_by_principal_id uuid not null references atlas.principals(id) on delete restrict,
  grant_basis jsonb not null default '{}'::jsonb,
  revoked_by_principal_id uuid references atlas.principals(id) on delete restrict,
  revoked_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sealed_treasury_operation_grants_state_v1
    check (grant_state in ('active','revoked','expired')),
  constraint sealed_treasury_operation_grants_validity_v1
    check (valid_until is null or valid_until>valid_from),
  constraint sealed_treasury_operation_grants_revocation_v1
    check (
      (grant_state='active' and revoked_at is null and revoked_by_principal_id is null)
      or
      (grant_state='revoked' and revoked_at is not null and revoked_by_principal_id is not null)
      or
      (grant_state='expired')
    ),
  constraint sealed_treasury_operation_grants_basis_v1
    check (jsonb_typeof(grant_basis)='object'),
  constraint sealed_treasury_operation_grants_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

create index if not exists sealed_treasury_operation_grants_lookup_idx_v1
  on atlas.sealed_treasury_operation_grants(
    endpoint_id,principal_id,operation_key,grant_state,valid_from,valid_until
  );

create table if not exists atlas.sealed_treasury_operation_warrants (
  id uuid primary key default gen_random_uuid(),
  endpoint_id uuid not null references atlas.sealed_treasury_endpoints(id) on delete restrict,
  principal_id uuid not null references atlas.principals(id) on delete restrict,
  operation_key text not null references atlas.sealed_treasury_operations(operation_key) on delete restrict,
  purpose_key text not null,
  warrant_token_hash bytea not null unique,
  warrant_state text not null default 'issued',
  issued_at timestamptz not null default now(),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  revoked_at timestamptz,
  reason_text text not null,
  request_context jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint sealed_treasury_operation_warrants_purpose_v1
    check (purpose_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint sealed_treasury_operation_warrants_state_v1
    check (warrant_state in ('issued','consumed','expired','revoked')),
  constraint sealed_treasury_operation_warrants_expiry_v1
    check (expires_at>issued_at),
  constraint sealed_treasury_operation_warrants_shape_v1
    check (
      (warrant_state='issued' and consumed_at is null and revoked_at is null)
      or
      (warrant_state='consumed' and consumed_at is not null and revoked_at is null)
      or
      (warrant_state='expired' and consumed_at is null)
      or
      (warrant_state='revoked' and consumed_at is null and revoked_at is not null)
    ),
  constraint sealed_treasury_operation_warrants_reason_v1
    check (btrim(reason_text)<>''),
  constraint sealed_treasury_operation_warrants_context_v1
    check (jsonb_typeof(request_context)='object')
);

create index if not exists sealed_treasury_operation_warrants_lookup_idx_v1
  on atlas.sealed_treasury_operation_warrants(
    endpoint_id,principal_id,operation_key,warrant_state,expires_at
  );

comment on table atlas.sealed_treasury_operation_warrants is
  'Short-lived one-time governance warrants. Only a SHA-256 hash of the bearer warrant is stored. The warrant authorizes one operation/purpose; it is not the treasury secret.';

create table if not exists atlas.sealed_treasury_operation_receipts (
  id uuid primary key default gen_random_uuid(),
  warrant_id uuid not null unique references atlas.sealed_treasury_operation_warrants(id) on delete restrict,
  outcome text not null,
  result_policy text not null,
  safe_result jsonb,
  carrier_key text not null,
  carrier_receipt_ref text,
  completed_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint sealed_treasury_operation_receipts_outcome_v1
    check (outcome in ('completed','failed')),
  constraint sealed_treasury_operation_receipts_policy_v1
    check (result_policy in ('boolean','string','receipt','ephemeral_reveal')),
  constraint sealed_treasury_operation_receipts_result_size_v1
    check (safe_result is null or octet_length(safe_result::text)<=4096),
  constraint sealed_treasury_operation_receipts_carrier_v1
    check (carrier_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint sealed_treasury_operation_receipts_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

create table if not exists atlas.sealed_treasury_operation_events (
  id uuid primary key default gen_random_uuid(),
  endpoint_id uuid not null references atlas.sealed_treasury_endpoints(id) on delete restrict,
  principal_id uuid references atlas.principals(id) on delete set null,
  event_key text not null,
  outcome text not null,
  operation_key text,
  purpose_key text,
  warrant_id uuid references atlas.sealed_treasury_operation_warrants(id) on delete set null,
  receipt_id uuid references atlas.sealed_treasury_operation_receipts(id) on delete set null,
  reason_text text,
  context jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint sealed_treasury_operation_events_event_v1
    check (event_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint sealed_treasury_operation_events_outcome_v1
    check (outcome in ('allowed','denied','completed','failed')),
  constraint sealed_treasury_operation_events_operation_v1
    check (operation_key is null or operation_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint sealed_treasury_operation_events_purpose_v1
    check (purpose_key is null or purpose_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint sealed_treasury_operation_events_context_v1
    check (jsonb_typeof(context)='object')
);

create index if not exists sealed_treasury_operation_events_idx_v1
  on atlas.sealed_treasury_operation_events(endpoint_id,occurred_at desc);

alter table atlas.sealed_treasury_operations enable row level security;
alter table atlas.sealed_treasury_endpoints enable row level security;
alter table atlas.sealed_treasury_operation_grants enable row level security;
alter table atlas.sealed_treasury_operation_warrants enable row level security;
alter table atlas.sealed_treasury_operation_receipts enable row level security;
alter table atlas.sealed_treasury_operation_events enable row level security;

revoke all on table atlas.sealed_treasury_operations from public,anon,authenticated;
revoke all on table atlas.sealed_treasury_endpoints from public,anon,authenticated,service_role;
revoke all on table atlas.sealed_treasury_operation_grants from public,anon,authenticated,service_role;
revoke all on table atlas.sealed_treasury_operation_warrants from public,anon,authenticated,service_role;
revoke all on table atlas.sealed_treasury_operation_receipts from public,anon,authenticated,service_role;
revoke all on table atlas.sealed_treasury_operation_events from public,anon,authenticated,service_role;
grant select on table atlas.sealed_treasury_operations to service_role;

create or replace function atlas.set_sealed_treasury_updated_at_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','atlas'
as $function$
begin
  new.updated_at=now();
  return new;
end
$function$;

drop trigger if exists sealed_treasury_operations_updated_at_v1
  on atlas.sealed_treasury_operations;
create trigger sealed_treasury_operations_updated_at_v1
before update on atlas.sealed_treasury_operations
for each row execute function atlas.set_sealed_treasury_updated_at_v1();

drop trigger if exists sealed_treasury_endpoints_updated_at_v1
  on atlas.sealed_treasury_endpoints;
create trigger sealed_treasury_endpoints_updated_at_v1
before update on atlas.sealed_treasury_endpoints
for each row execute function atlas.set_sealed_treasury_updated_at_v1();

drop trigger if exists sealed_treasury_operation_grants_updated_at_v1
  on atlas.sealed_treasury_operation_grants;
create trigger sealed_treasury_operation_grants_updated_at_v1
before update on atlas.sealed_treasury_operation_grants
for each row execute function atlas.set_sealed_treasury_updated_at_v1();

create or replace function atlas.prevent_sealed_treasury_event_mutation_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','atlas'
as $function$
begin
  raise exception 'Sealed treasury operation events are append-only.'
    using errcode='42501';
end
$function$;

drop trigger if exists sealed_treasury_events_append_only_v1
  on atlas.sealed_treasury_operation_events;
create trigger sealed_treasury_events_append_only_v1
before update or delete on atlas.sealed_treasury_operation_events
for each row execute function atlas.prevent_sealed_treasury_event_mutation_v1();

create or replace function atlas.write_sealed_treasury_event_internal_v1(
  p_endpoint_id uuid,
  p_principal_id uuid,
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
  insert into atlas.sealed_treasury_operation_events(
    endpoint_id,principal_id,event_key,outcome,operation_key,purpose_key,
    warrant_id,receipt_id,reason_text,context
  )
  values(
    p_endpoint_id,p_principal_id,lower(btrim(p_event_key)),lower(btrim(p_outcome)),
    case when p_operation_key is null then null else lower(btrim(p_operation_key)) end,
    case when p_purpose_key is null then null else lower(btrim(p_purpose_key)) end,
    p_warrant_id,p_receipt_id,nullif(btrim(p_reason_text),''),
    coalesce(p_context,'{}'::jsonb)
  )
  returning id into v_id;
  return v_id;
end
$function$;

revoke all on function atlas.write_sealed_treasury_event_internal_v1(
  uuid,uuid,text,text,text,text,uuid,uuid,text,jsonb
) from public,anon,authenticated,service_role;

create or replace function atlas.principal_has_sealed_treasury_operation_v1(
  p_principal_id uuid,
  p_endpoint_id uuid,
  p_operation_key text,
  p_purpose_key text default null
)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog','atlas'
as $function$
  select exists(
    select 1
    from atlas.sealed_treasury_operation_grants g
    join atlas.sealed_treasury_endpoints e
      on e.id=g.endpoint_id and e.endpoint_state='active'
    join atlas.sealed_treasury_operations o
      on o.operation_key=g.operation_key and o.operation_state='active'
    where g.endpoint_id=p_endpoint_id
      and g.principal_id=p_principal_id
      and g.operation_key=lower(btrim(p_operation_key))
      and g.grant_state='active'
      and g.valid_from<=now()
      and (g.valid_until is null or g.valid_until>now())
      and (
        cardinality(g.purpose_scope)=0
        or (
          p_purpose_key is not null
          and lower(btrim(p_purpose_key))=any(g.purpose_scope)
        )
      )
  );
$function$;

revoke all on function atlas.principal_has_sealed_treasury_operation_v1(
  uuid,uuid,text,text
) from public,anon,authenticated;
grant execute on function atlas.principal_has_sealed_treasury_operation_v1(
  uuid,uuid,text,text
) to service_role;

create or replace function atlas.create_sealed_treasury_endpoint_service_v1(
  p_ledger_id uuid,
  p_created_by_principal_id uuid,
  p_stable_key text,
  p_title text,
  p_carrier_key text,
  p_carrier_locator text,
  p_carrier_version text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_key text:=lower(btrim(coalesce(p_stable_key,'')));
  v_carrier text:=lower(btrim(coalesce(p_carrier_key,'')));
  v_endpoint atlas.sealed_treasury_endpoints%rowtype;
  v_operation text;
begin
  if not atlas.principal_has_ledger_authority_v1(
    p_created_by_principal_id,p_ledger_id
  ) then
    raise exception 'Principal lacks governing authority over Ledger.'
      using errcode='42501';
  end if;

  if not exists(
    select 1 from atlas.ledgers l
    where l.id=p_ledger_id and l.status='active'
  ) then
    raise exception 'Active Ledger not found.' using errcode='P0002';
  end if;

  if v_key !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
     or v_carrier !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
     or btrim(coalesce(p_title,''))=''
     or btrim(coalesce(p_carrier_locator,''))='' then
    raise exception 'Treasury endpoint key/title/carrier locator are invalid.'
      using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then
    raise exception 'Treasury endpoint metadata must be a JSON object.'
      using errcode='22023';
  end if;

  insert into atlas.sealed_treasury_endpoints(
    ledger_id,stable_key,title,endpoint_kind,endpoint_state,
    carrier_key,carrier_locator,carrier_version,created_by_principal_id,metadata
  )
  values(
    p_ledger_id,v_key,btrim(p_title),'bank_destination','active',
    v_carrier,btrim(p_carrier_locator),nullif(btrim(p_carrier_version),''),
    p_created_by_principal_id,coalesce(p_metadata,'{}'::jsonb)
  )
  returning * into v_endpoint;

  foreach v_operation in array array[
    'observe_existence','delegate_operation','audit_operations'
  ]::text[]
  loop
    insert into atlas.sealed_treasury_operation_grants(
      endpoint_id,principal_id,operation_key,purpose_scope,grant_state,
      valid_from,granted_by_principal_id,grant_basis,metadata
    )
    values(
      v_endpoint.id,p_created_by_principal_id,v_operation,'{}'::text[],'active',
      now(),p_created_by_principal_id,
      jsonb_build_object('basis','endpoint_creator_bootstrap'),
      '{}'::jsonb
    );
  end loop;

  perform atlas.write_sealed_treasury_event_internal_v1(
    v_endpoint.id,p_created_by_principal_id,'endpoint_create','completed',
    null,null,null,null,'sealed treasury endpoint established',
    jsonb_build_object('ledgerId',p_ledger_id,'stableKey',v_key)
  );

  return jsonb_build_object(
    'contractVersion','sealed_treasury_endpoint_v1',
    'endpointId',v_endpoint.id,
    'ledgerId',v_endpoint.ledger_id,
    'stableKey',v_endpoint.stable_key,
    'title',v_endpoint.title,
    'endpointKind',v_endpoint.endpoint_kind,
    'endpointState',v_endpoint.endpoint_state,
    'carrierKey',v_endpoint.carrier_key
  );
end
$function$;

create or replace function atlas.grant_sealed_treasury_operation_service_v1(
  p_endpoint_id uuid,
  p_target_principal_id uuid,
  p_operation_key text,
  p_granted_by_principal_id uuid,
  p_purpose_scope text[] default '{}'::text[],
  p_valid_from timestamptz default now(),
  p_valid_until timestamptz default null,
  p_grant_basis jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_operation text:=lower(btrim(coalesce(p_operation_key,'')));
  v_scope text[];
  v_start timestamptz:=coalesce(p_valid_from,now());
  v_grant atlas.sealed_treasury_operation_grants%rowtype;
  v_allowed boolean;
begin
  v_allowed:=atlas.principal_has_sealed_treasury_operation_v1(
    p_granted_by_principal_id,p_endpoint_id,'delegate_operation',null
  );

  if not v_allowed then
    perform atlas.write_sealed_treasury_event_internal_v1(
      p_endpoint_id,p_granted_by_principal_id,'operation_grant','denied',
      'delegate_operation',null,null,null,
      'grantor lacks delegation authority',
      jsonb_build_object(
        'targetPrincipalId',p_target_principal_id,
        'requestedOperation',v_operation
      )
    );
    return jsonb_build_object(
      'contractVersion','sealed_treasury_operation_grant_v1',
      'authorized',false,
      'reason','delegate_operation_required'
    );
  end if;

  if not exists(
    select 1 from atlas.principals p
    where p.id=p_target_principal_id and p.status='active'
  ) then
    raise exception 'Active target Principal not found.' using errcode='P0002';
  end if;

  if not exists(
    select 1 from atlas.sealed_treasury_operations o
    where o.operation_key=v_operation and o.operation_state='active'
  ) then
    raise exception 'Treasury operation is missing or inactive.'
      using errcode='P0002';
  end if;

  select coalesce(array_agg(distinct lower(btrim(x)) order by lower(btrim(x))),'{}'::text[])
  into v_scope
  from unnest(coalesce(p_purpose_scope,'{}'::text[])) t(x);

  if exists(
    select 1 from unnest(v_scope) x
    where x !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
  ) then
    raise exception 'Purpose scope contains an invalid key.'
      using errcode='22023';
  end if;

  if v_operation in (
    'verify_destination','compare_destination','submit_payment_destination',
    'reveal_hint','reveal_full'
  ) and cardinality(v_scope)=0 then
    raise exception 'Operational treasury authority requires an explicit purpose scope.'
      using errcode='22023';
  end if;

  if p_valid_until is not null and p_valid_until<=v_start then
    raise exception 'Grant end must be after grant start.' using errcode='22023';
  end if;

  if v_operation='reveal_full'
     and (
       p_valid_until is null
       or p_valid_until>v_start+interval '1 hour'
     ) then
    raise exception 'Full-reveal authority must be explicitly time-bounded to at most one hour.'
      using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_grant_basis,'{}'::jsonb))<>'object'
     or jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then
    raise exception 'Grant basis/metadata must be JSON objects.'
      using errcode='22023';
  end if;

  insert into atlas.sealed_treasury_operation_grants(
    endpoint_id,principal_id,operation_key,purpose_scope,grant_state,
    valid_from,valid_until,granted_by_principal_id,grant_basis,metadata
  )
  values(
    p_endpoint_id,p_target_principal_id,v_operation,v_scope,'active',
    v_start,p_valid_until,p_granted_by_principal_id,
    coalesce(p_grant_basis,'{}'::jsonb),coalesce(p_metadata,'{}'::jsonb)
  )
  returning * into v_grant;

  perform atlas.write_sealed_treasury_event_internal_v1(
    p_endpoint_id,p_granted_by_principal_id,'operation_grant','completed',
    'delegate_operation',null,null,null,'treasury operation authority granted',
    jsonb_build_object(
      'grantId',v_grant.id,
      'targetPrincipalId',p_target_principal_id,
      'grantedOperation',v_operation,
      'purposeScope',to_jsonb(v_scope),
      'validUntil',p_valid_until
    )
  );

  return jsonb_build_object(
    'contractVersion','sealed_treasury_operation_grant_v1',
    'authorized',true,
    'grantId',v_grant.id,
    'endpointId',v_grant.endpoint_id,
    'principalId',v_grant.principal_id,
    'operationKey',v_grant.operation_key,
    'purposeScope',to_jsonb(v_grant.purpose_scope),
    'validFrom',v_grant.valid_from,
    'validUntil',v_grant.valid_until
  );
end
$function$;

create or replace function atlas.request_sealed_treasury_operation_service_v1(
  p_endpoint_id uuid,
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
  v_operation_key text:=lower(btrim(coalesce(p_operation_key,'')));
  v_purpose text:=lower(btrim(coalesce(p_purpose_key,'')));
  v_operation atlas.sealed_treasury_operations%rowtype;
  v_endpoint atlas.sealed_treasury_endpoints%rowtype;
  v_allowed boolean;
  v_token text;
  v_token_hash bytea;
  v_warrant atlas.sealed_treasury_operation_warrants%rowtype;
begin
  if v_purpose !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
     or btrim(coalesce(p_reason,''))='' then
    raise exception 'Purpose and operation reason are required.'
      using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_context,'{}'::jsonb))<>'object' then
    raise exception 'Operation context must be a JSON object.'
      using errcode='22023';
  end if;

  select * into v_operation
  from atlas.sealed_treasury_operations o
  where o.operation_key=v_operation_key
    and o.operation_state='active';

  if v_operation.operation_key is null then
    raise exception 'Treasury operation is missing or inactive.'
      using errcode='P0002';
  end if;

  select * into v_endpoint
  from atlas.sealed_treasury_endpoints e
  where e.id=p_endpoint_id and e.endpoint_state='active';

  if v_endpoint.id is null then
    raise exception 'Active sealed treasury endpoint not found.'
      using errcode='P0002';
  end if;

  v_allowed:=atlas.principal_has_sealed_treasury_operation_v1(
    p_principal_id,p_endpoint_id,v_operation_key,v_purpose
  );

  if not v_allowed then
    perform atlas.write_sealed_treasury_event_internal_v1(
      p_endpoint_id,p_principal_id,'operation_request','denied',
      v_operation_key,v_purpose,null,null,p_reason,
      coalesce(p_context,'{}'::jsonb)
    );
    return jsonb_build_object(
      'contractVersion','sealed_treasury_operation_request_v1',
      'authorized',false,
      'operationKey',v_operation_key,
      'purposeKey',v_purpose,
      'reason','operation_authority_required'
    );
  end if;

  if not v_operation.requires_carrier then
    perform atlas.write_sealed_treasury_event_internal_v1(
      p_endpoint_id,p_principal_id,'operation_request','completed',
      v_operation_key,v_purpose,null,null,p_reason,
      coalesce(p_context,'{}'::jsonb)
    );

    if v_operation_key='observe_existence' then
      return jsonb_build_object(
        'contractVersion','sealed_treasury_operation_request_v1',
        'authorized',true,
        'requiresCarrier',false,
        'operationKey',v_operation_key,
        'purposeKey',v_purpose,
        'endpoint',jsonb_build_object(
          'endpointId',v_endpoint.id,
          'ledgerId',v_endpoint.ledger_id,
          'stableKey',v_endpoint.stable_key,
          'title',v_endpoint.title,
          'endpointKind',v_endpoint.endpoint_kind,
          'endpointState',v_endpoint.endpoint_state,
          'carrierKey',v_endpoint.carrier_key
        )
      );
    end if;

    return jsonb_build_object(
      'contractVersion','sealed_treasury_operation_request_v1',
      'authorized',true,
      'requiresCarrier',false,
      'operationKey',v_operation_key,
      'purposeKey',v_purpose
    );
  end if;

  v_token:=encode(extensions.gen_random_bytes(32),'hex');
  v_token_hash:=extensions.digest(v_token,'sha256');

  insert into atlas.sealed_treasury_operation_warrants(
    endpoint_id,principal_id,operation_key,purpose_key,warrant_token_hash,
    warrant_state,issued_at,expires_at,reason_text,request_context
  )
  values(
    p_endpoint_id,p_principal_id,v_operation_key,v_purpose,v_token_hash,
    'issued',now(),now()+make_interval(secs=>v_operation.default_warrant_ttl_seconds),
    btrim(p_reason),coalesce(p_context,'{}'::jsonb)
  )
  returning * into v_warrant;

  perform atlas.write_sealed_treasury_event_internal_v1(
    p_endpoint_id,p_principal_id,'operation_request','allowed',
    v_operation_key,v_purpose,v_warrant.id,null,p_reason,
    coalesce(p_context,'{}'::jsonb)
  );

  return jsonb_build_object(
    'contractVersion','sealed_treasury_operation_request_v1',
    'authorized',true,
    'requiresCarrier',true,
    'operationKey',v_operation_key,
    'purposeKey',v_purpose,
    'warrantId',v_warrant.id,
    'warrantToken',v_token,
    'expiresAt',v_warrant.expires_at,
    'carrier',jsonb_build_object(
      'carrierKey',v_endpoint.carrier_key,
      'carrierLocator',v_endpoint.carrier_locator,
      'carrierVersion',v_endpoint.carrier_version
    ),
    'resultPolicy',v_operation.result_policy,
    'revealsPlaintext',v_operation.reveals_plaintext
  );
end
$function$;

create or replace function atlas.complete_sealed_treasury_operation_service_v1(
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
  v_hash bytea;
  v_warrant atlas.sealed_treasury_operation_warrants%rowtype;
  v_operation atlas.sealed_treasury_operations%rowtype;
  v_endpoint atlas.sealed_treasury_endpoints%rowtype;
  v_outcome text:=lower(btrim(coalesce(p_outcome,'')));
  v_carrier text:=lower(btrim(coalesce(p_carrier_key,'')));
  v_receipt atlas.sealed_treasury_operation_receipts%rowtype;
begin
  if length(coalesce(p_warrant_token,''))<32 then
    raise exception 'Warrant token is invalid.' using errcode='22023';
  end if;

  v_hash:=extensions.digest(p_warrant_token,'sha256');

  select * into v_warrant
  from atlas.sealed_treasury_operation_warrants w
  where w.warrant_token_hash=v_hash
  for update;

  if v_warrant.id is null then
    raise exception 'Operation warrant not found.' using errcode='P0002';
  end if;

  if v_warrant.warrant_state<>'issued' then
    raise exception 'Operation warrant is no longer usable.' using errcode='22023';
  end if;

  if v_warrant.expires_at<=now() then
    update atlas.sealed_treasury_operation_warrants
    set warrant_state='expired'
    where id=v_warrant.id;

    perform atlas.write_sealed_treasury_event_internal_v1(
      v_warrant.endpoint_id,v_warrant.principal_id,'carrier_completion','failed',
      v_warrant.operation_key,v_warrant.purpose_key,v_warrant.id,null,
      'operation warrant expired before carrier completion','{}'::jsonb
    );
    return jsonb_build_object(
      'contractVersion','sealed_treasury_operation_completion_v1',
      'completed',false,
      'reason','warrant_expired'
    );
  end if;

  select * into v_operation
  from atlas.sealed_treasury_operations o
  where o.operation_key=v_warrant.operation_key;

  select * into v_endpoint
  from atlas.sealed_treasury_endpoints e
  where e.id=v_warrant.endpoint_id;

  if v_carrier<>v_endpoint.carrier_key then
    raise exception 'Carrier key does not match endpoint carrier.'
      using errcode='42501';
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

  if v_outcome='completed' then
    if v_operation.result_policy='boolean'
       and jsonb_typeof(p_safe_result)<>'boolean' then
      raise exception 'This treasury operation may return only a boolean.'
        using errcode='22023';
    elsif v_operation.result_policy='string'
       and (
         jsonb_typeof(p_safe_result)<>'string'
         or length(p_safe_result#>>'{}')>256
       ) then
      raise exception 'This treasury operation may return only a bounded string.'
        using errcode='22023';
    elsif v_operation.result_policy='receipt'
       and jsonb_typeof(p_safe_result)<>'object' then
      raise exception 'This treasury operation must return a bounded receipt object.'
        using errcode='22023';
    elsif v_operation.result_policy='ephemeral_reveal'
       and p_safe_result is distinct from '{"delivered":true}'::jsonb then
      raise exception 'Full reveal plaintext must not be persisted in the canonical receipt.'
        using errcode='22023';
    end if;
  else
    if p_safe_result is not null
       and (
         jsonb_typeof(p_safe_result)<>'object'
         or (p_safe_result-'errorClass')<>'{}'::jsonb
       ) then
      raise exception 'Failed carrier result may contain only errorClass metadata.'
        using errcode='22023';
    end if;
  end if;

  update atlas.sealed_treasury_operation_warrants
  set warrant_state='consumed',
      consumed_at=now()
  where id=v_warrant.id;

  insert into atlas.sealed_treasury_operation_receipts(
    warrant_id,outcome,result_policy,safe_result,carrier_key,
    carrier_receipt_ref,metadata
  )
  values(
    v_warrant.id,v_outcome,v_operation.result_policy,p_safe_result,
    v_carrier,nullif(btrim(p_carrier_receipt_ref),''),
    coalesce(p_metadata,'{}'::jsonb)
  )
  returning * into v_receipt;

  perform atlas.write_sealed_treasury_event_internal_v1(
    v_warrant.endpoint_id,v_warrant.principal_id,'carrier_completion',
    case when v_outcome='completed' then 'completed' else 'failed' end,
    v_warrant.operation_key,v_warrant.purpose_key,v_warrant.id,v_receipt.id,
    'sealed treasury carrier completed operation',
    jsonb_build_object('carrierKey',v_carrier)
  );

  return jsonb_build_object(
    'contractVersion','sealed_treasury_operation_completion_v1',
    'completed',v_outcome='completed',
    'receiptId',v_receipt.id,
    'warrantId',v_warrant.id,
    'operationKey',v_warrant.operation_key,
    'purposeKey',v_warrant.purpose_key,
    'resultPolicy',v_receipt.result_policy,
    'safeResult',v_receipt.safe_result,
    'carrierReceiptRef',v_receipt.carrier_receipt_ref
  );
end
$function$;

create or replace function atlas.read_sealed_treasury_operation_events_service_v1(
  p_endpoint_id uuid,
  p_principal_id uuid,
  p_limit integer default 100,
  p_reason text default 'treasury operation audit review'
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_allowed boolean;
  v_limit integer:=greatest(1,least(coalesce(p_limit,100),500));
  v_events jsonb;
begin
  v_allowed:=atlas.principal_has_sealed_treasury_operation_v1(
    p_principal_id,p_endpoint_id,'audit_operations',null
  );

  if not v_allowed then
    perform atlas.write_sealed_treasury_event_internal_v1(
      p_endpoint_id,p_principal_id,'audit_read','denied',
      'audit_operations',null,null,null,p_reason,
      jsonb_build_object('limit',v_limit)
    );
    return jsonb_build_object(
      'contractVersion','sealed_treasury_operation_audit_v1',
      'authorized',false,
      'reason','audit_operations_required',
      'events','[]'::jsonb
    );
  end if;

  perform atlas.write_sealed_treasury_event_internal_v1(
    p_endpoint_id,p_principal_id,'audit_read','allowed',
    'audit_operations',null,null,null,p_reason,
    jsonb_build_object('limit',v_limit)
  );

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'eventId',q.id,
      'principalId',q.principal_id,
      'eventKey',q.event_key,
      'outcome',q.outcome,
      'operationKey',q.operation_key,
      'purposeKey',q.purpose_key,
      'warrantId',q.warrant_id,
      'receiptId',q.receipt_id,
      'reason',q.reason_text,
      'context',q.context,
      'occurredAt',q.occurred_at
    )
    order by q.occurred_at desc,q.id
  ),'[]'::jsonb)
  into v_events
  from (
    select *
    from atlas.sealed_treasury_operation_events e
    where e.endpoint_id=p_endpoint_id
    order by e.occurred_at desc,e.id
    limit v_limit
  ) q;

  return jsonb_build_object(
    'contractVersion','sealed_treasury_operation_audit_v1',
    'authorized',true,
    'endpointId',p_endpoint_id,
    'events',v_events
  );
end
$function$;

revoke all on function atlas.create_sealed_treasury_endpoint_service_v1(
  uuid,uuid,text,text,text,text,text,jsonb
) from public,anon,authenticated;
grant execute on function atlas.create_sealed_treasury_endpoint_service_v1(
  uuid,uuid,text,text,text,text,text,jsonb
) to service_role;

revoke all on function atlas.grant_sealed_treasury_operation_service_v1(
  uuid,uuid,text,uuid,text[],timestamptz,timestamptz,jsonb,jsonb
) from public,anon,authenticated;
grant execute on function atlas.grant_sealed_treasury_operation_service_v1(
  uuid,uuid,text,uuid,text[],timestamptz,timestamptz,jsonb,jsonb
) to service_role;

revoke all on function atlas.request_sealed_treasury_operation_service_v1(
  uuid,uuid,text,text,text,jsonb
) from public,anon,authenticated;
grant execute on function atlas.request_sealed_treasury_operation_service_v1(
  uuid,uuid,text,text,text,jsonb
) to service_role;

revoke all on function atlas.complete_sealed_treasury_operation_service_v1(
  text,text,text,jsonb,text,jsonb
) from public,anon,authenticated;
grant execute on function atlas.complete_sealed_treasury_operation_service_v1(
  text,text,text,jsonb,text,jsonb
) to service_role;

revoke all on function atlas.read_sealed_treasury_operation_events_service_v1(
  uuid,uuid,integer,text
) from public,anon,authenticated;
grant execute on function atlas.read_sealed_treasury_operation_events_service_v1(
  uuid,uuid,integer,text
) to service_role;
