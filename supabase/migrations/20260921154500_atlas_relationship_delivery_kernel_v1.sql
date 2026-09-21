begin;

-- Atlas Relationship Delivery Kernel v1
--
-- Universal law:
--   source truth != recipient relationship != delivery grant != credential
--   != session != projection != response/result.
--
-- This tranche makes secure no-login delivery possible without creating a
-- universal task model. The first typed relationship adapter is the live
-- Institutional Person Record. Household delivery can add its own typed binding
-- over this same grant/credential/session kernel later.

create table atlas.relationship_delivery_grants (
  id uuid primary key default gen_random_uuid(),
  recipient_person_id uuid not null references atlas.people(id) on delete restrict,
  status text not null default 'active'
    check (status in ('active','revoked')),
  projection_contracts text[] not null,
  response_contracts text[] not null default '{}'::text[],
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  issuance_provenance jsonb not null default '{}'::jsonb
    check (jsonb_typeof(issuance_provenance)='object'),
  revoked_at timestamptz,
  revoke_reason text,
  revocation_provenance jsonb not null default '{}'::jsonb
    check (jsonb_typeof(revocation_provenance)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (cardinality(projection_contracts) > 0),
  check (array_position(projection_contracts,null) is null),
  check (array_position(response_contracts,null) is null),
  check (valid_until is null or valid_until > valid_from),
  check (
    (status='active' and revoked_at is null)
    or
    (status='revoked' and revoked_at is not null)
  )
);

create index relationship_delivery_grants_recipient_status_idx
  on atlas.relationship_delivery_grants(recipient_person_id,status,valid_until);

comment on table atlas.relationship_delivery_grants is
  'Revocable admission for one canonical Person to receive named projection contracts and invoke named response contracts through a governed relationship. A grant is not identity, responsibility, source truth, decision authority, broad permission, or a Personal Atlas.';

comment on column atlas.relationship_delivery_grants.projection_contracts is
  'Named/versioned delivery adapters that may project bounded source-owned reality. These are adapter contracts, not generic action permissions.';

comment on column atlas.relationship_delivery_grants.response_contracts is
  'Named/versioned source-domain response adapters that may be invoked through this delivery grant. A response contract never creates generic mutation authority.';

create table atlas.relationship_delivery_institution_bindings (
  grant_id uuid primary key
    references atlas.relationship_delivery_grants(id) on delete cascade,
  organization_id uuid not null
    references atlas.organizations(id) on delete cascade,
  institutional_person_record_id uuid not null,
  binding_provenance jsonb not null default '{}'::jsonb
    check (jsonb_typeof(binding_provenance)='object'),
  created_at timestamptz not null default now(),
  constraint relationship_delivery_institution_binding_ipr_org_fk
    foreign key (organization_id,institutional_person_record_id)
    references atlas.institutional_person_records(organization_id,id)
    on delete restrict
);

create index relationship_delivery_institution_bindings_ipr_idx
  on atlas.relationship_delivery_institution_bindings(
    organization_id,institutional_person_record_id
  );

comment on table atlas.relationship_delivery_institution_bindings is
  'Typed relationship adapter binding a universal Relationship Delivery Grant to one Institutional Person Record. It does not create the institutional relationship or any Company Work responsibility.';

create table atlas.relationship_delivery_bootstrap_credentials (
  id uuid primary key default gen_random_uuid(),
  grant_id uuid not null
    references atlas.relationship_delivery_grants(id) on delete cascade,
  secret_hash text not null unique,
  status text not null default 'active'
    check (status in ('active','redeemed','revoked')),
  issued_at timestamptz not null default now(),
  expires_at timestamptz not null,
  redeemed_at timestamptz,
  revoked_at timestamptz,
  provenance jsonb not null default '{}'::jsonb
    check (jsonb_typeof(provenance)='object'),
  check (expires_at > issued_at),
  check (
    (status='active' and redeemed_at is null and revoked_at is null)
    or
    (status='redeemed' and redeemed_at is not null and revoked_at is null)
    or
    (status='revoked' and revoked_at is not null)
  )
);

create index relationship_delivery_bootstrap_credentials_grant_idx
  on atlas.relationship_delivery_bootstrap_credentials(grant_id,status,expires_at);

comment on table atlas.relationship_delivery_bootstrap_credentials is
  'One-time bearer bootstrap carriers for Relationship Delivery. Only a one-way SHA-256 hash is stored; raw bootstrap material is returned once by a service-only issuance function and must never be persisted here.';

create table atlas.relationship_delivery_sessions (
  id uuid primary key default gen_random_uuid(),
  grant_id uuid not null
    references atlas.relationship_delivery_grants(id) on delete cascade,
  token_hash text not null unique,
  status text not null default 'active'
    check (status in ('active','revoked')),
  issued_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  check (expires_at > issued_at),
  check (
    (status='active' and revoked_at is null)
    or
    (status='revoked' and revoked_at is not null)
  )
);

create index relationship_delivery_sessions_grant_idx
  on atlas.relationship_delivery_sessions(grant_id,status,expires_at);

comment on table atlas.relationship_delivery_sessions is
  'Short-lived server-resolved possession sessions carrying one Relationship Delivery Grant. Session possession is not Person identity or responsibility; every read/write must revalidate the grant and typed relationship.';

alter table atlas.relationship_delivery_grants enable row level security;
alter table atlas.relationship_delivery_institution_bindings enable row level security;
alter table atlas.relationship_delivery_bootstrap_credentials enable row level security;
alter table atlas.relationship_delivery_sessions enable row level security;

revoke all on table atlas.relationship_delivery_grants
  from public,anon,authenticated,service_role;
revoke all on table atlas.relationship_delivery_institution_bindings
  from public,anon,authenticated,service_role;
revoke all on table atlas.relationship_delivery_bootstrap_credentials
  from public,anon,authenticated,service_role;
revoke all on table atlas.relationship_delivery_sessions
  from public,anon,authenticated,service_role;

create or replace function atlas.relationship_delivery_contract_array_normalize_v1(
  p_contracts text[],
  p_require_nonempty boolean
)
returns text[]
language plpgsql
immutable
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_contracts text[];
begin
  select coalesce(array_agg(x order by x),'{}'::text[])
  into v_contracts
  from (
    select distinct btrim(v) as x
    from unnest(coalesce(p_contracts,'{}'::text[])) as u(v)
    where v is not null and btrim(v)<>''
  ) q;

  if p_require_nonempty and cardinality(v_contracts)=0 then
    raise exception 'At least one projection contract is required.'
      using errcode='23514';
  end if;

  return v_contracts;
end;
$function$;

revoke all on function atlas.relationship_delivery_contract_array_normalize_v1(text[],boolean)
  from public,anon,authenticated,service_role;

create or replace function atlas.relationship_delivery_secret_hash_v1(
  p_secret text
)
returns text
language plpgsql
immutable
security definer
set search_path=pg_catalog,atlas,extensions
as $function$
begin
  if p_secret is null or length(p_secret)<32 then
    raise exception 'Relationship Delivery credential is invalid.'
      using errcode='22023';
  end if;

  return encode(extensions.digest(p_secret,'sha256'),'hex');
end;
$function$;

revoke all on function atlas.relationship_delivery_secret_hash_v1(text)
  from public,anon,authenticated,service_role;

create or replace function atlas.guard_relationship_delivery_institution_binding_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_recipient_person_id uuid;
  v_ipr_person_id uuid;
begin
  select g.recipient_person_id
  into v_recipient_person_id
  from atlas.relationship_delivery_grants g
  where g.id=new.grant_id;

  select ipr.person_id
  into v_ipr_person_id
  from atlas.institutional_person_records ipr
  where ipr.id=new.institutional_person_record_id
    and ipr.organization_id=new.organization_id;

  if v_recipient_person_id is null or v_ipr_person_id is null
     or v_recipient_person_id<>v_ipr_person_id then
    raise exception 'Relationship Delivery institutional binding must resolve the grant recipient to the same canonical Person.'
      using errcode='23514';
  end if;

  return new;
end;
$function$;

revoke all on function atlas.guard_relationship_delivery_institution_binding_v1()
  from public,anon,authenticated,service_role;

create trigger relationship_delivery_institution_binding_guard_v1
before insert or update of grant_id,organization_id,institutional_person_record_id
on atlas.relationship_delivery_institution_bindings
for each row execute function atlas.guard_relationship_delivery_institution_binding_v1();

create or replace function atlas.relationship_delivery_binding_context_internal_v1(
  p_grant_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_context jsonb;
begin
  select jsonb_build_object(
    'kind','institutional_person_record',
    'organizationId',b.organization_id,
    'institutionalPersonRecordId',ipr.id,
    'personId',ipr.person_id
  )
  into v_context
  from atlas.relationship_delivery_institution_bindings b
  join atlas.institutional_person_records ipr
    on ipr.id=b.institutional_person_record_id
   and ipr.organization_id=b.organization_id
  join atlas.people p
    on p.id=ipr.person_id
  where b.grant_id=p_grant_id
    and ipr.status='active'
    and p.status='active';

  if v_context is null then
    raise exception 'Relationship Delivery grant has no active supported recipient relationship.'
      using errcode='42501';
  end if;

  return v_context;
end;
$function$;

revoke all on function atlas.relationship_delivery_binding_context_internal_v1(uuid)
  from public,anon,authenticated,service_role;

create or replace function atlas.relationship_delivery_session_context_internal_v1(
  p_session_token text
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_hash text;
  v_session record;
  v_relationship jsonb;
begin
  v_hash:=atlas.relationship_delivery_secret_hash_v1(p_session_token);

  select
    s.id as session_id,
    s.grant_id,
    s.expires_at as session_expires_at,
    g.recipient_person_id,
    g.projection_contracts,
    g.response_contracts,
    g.valid_from,
    g.valid_until
  into v_session
  from atlas.relationship_delivery_sessions s
  join atlas.relationship_delivery_grants g on g.id=s.grant_id
  where s.token_hash=v_hash
    and s.status='active'
    and s.expires_at>now()
    and g.status='active'
    and g.valid_from<=now()
    and (g.valid_until is null or g.valid_until>now());

  if v_session.session_id is null then
    raise exception 'Relationship Delivery session is invalid or unavailable.'
      using errcode='42501';
  end if;

  v_relationship:=atlas.relationship_delivery_binding_context_internal_v1(v_session.grant_id);

  if (v_relationship->>'personId')::uuid<>v_session.recipient_person_id then
    raise exception 'Relationship Delivery relationship no longer resolves the admitted recipient.'
      using errcode='42501';
  end if;

  return jsonb_build_object(
    'sessionId',v_session.session_id,
    'grantId',v_session.grant_id,
    'recipientPersonId',v_session.recipient_person_id,
    'projectionContracts',to_jsonb(v_session.projection_contracts),
    'responseContracts',to_jsonb(v_session.response_contracts),
    'sessionExpiresAt',v_session.session_expires_at,
    'grantValidUntil',v_session.valid_until,
    'relationship',v_relationship
  );
end;
$function$;

revoke all on function atlas.relationship_delivery_session_context_internal_v1(text)
  from public,anon,authenticated,service_role;

create or replace function atlas.relationship_delivery_session_contract_internal_v1(
  p_session_token text,
  p_contract_kind text,
  p_contract_key text
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_context jsonb;
  v_contracts text[];
begin
  if p_contract_kind not in ('projection','response')
     or p_contract_key is null or btrim(p_contract_key)='' then
    raise exception 'Relationship Delivery contract request is invalid.'
      using errcode='22023';
  end if;

  v_context:=atlas.relationship_delivery_session_context_internal_v1(p_session_token);

  if p_contract_kind='projection' then
    select coalesce(array_agg(value #>> '{}'),'{}'::text[])
    into v_contracts
    from jsonb_array_elements(v_context->'projectionContracts');
  else
    select coalesce(array_agg(value #>> '{}'),'{}'::text[])
    into v_contracts
    from jsonb_array_elements(v_context->'responseContracts');
  end if;

  if not (btrim(p_contract_key)=any(v_contracts)) then
    raise exception 'Relationship Delivery contract is not admitted by this grant.'
      using errcode='42501';
  end if;

  return v_context;
end;
$function$;

revoke all on function atlas.relationship_delivery_session_contract_internal_v1(text,text,text)
  from public,anon,authenticated,service_role;

create or replace function atlas.issue_institutional_relationship_delivery_service_v1(
  p_institutional_person_record_id uuid,
  p_projection_contracts text[],
  p_response_contracts text[] default '{}'::text[],
  p_grant_valid_until timestamptz default null,
  p_bootstrap_expires_at timestamptz default (now()+interval '7 days'),
  p_provenance jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,extensions
as $function$
declare
  v_ipr record;
  v_projection_contracts text[];
  v_response_contracts text[];
  v_grant_id uuid;
  v_credential_id uuid;
  v_raw_secret text;
  v_secret_hash text;
  v_bootstrap_expires_at timestamptz;
begin
  if p_provenance is null or jsonb_typeof(p_provenance)<>'object' then
    raise exception 'Relationship Delivery issuance provenance must be an object.'
      using errcode='22023';
  end if;

  v_projection_contracts:=
    atlas.relationship_delivery_contract_array_normalize_v1(
      p_projection_contracts,true
    );
  v_response_contracts:=
    atlas.relationship_delivery_contract_array_normalize_v1(
      p_response_contracts,false
    );

  select
    ipr.id,
    ipr.organization_id,
    ipr.person_id,
    ipr.status,
    p.status as person_status
  into v_ipr
  from atlas.institutional_person_records ipr
  join atlas.people p on p.id=ipr.person_id
  where ipr.id=p_institutional_person_record_id;

  if v_ipr.id is null or v_ipr.status<>'active' or v_ipr.person_status<>'active' then
    raise exception 'Institutional recipient relationship is unavailable.'
      using errcode='42501';
  end if;

  if p_grant_valid_until is not null and p_grant_valid_until<=now() then
    raise exception 'Relationship Delivery grant validity must extend into the future.'
      using errcode='22023';
  end if;

  v_bootstrap_expires_at:=coalesce(
    p_bootstrap_expires_at,
    now()+interval '7 days'
  );

  if p_grant_valid_until is not null then
    v_bootstrap_expires_at:=least(v_bootstrap_expires_at,p_grant_valid_until);
  end if;

  if v_bootstrap_expires_at<=now() then
    raise exception 'Relationship Delivery bootstrap validity must extend into the future.'
      using errcode='22023';
  end if;

  insert into atlas.relationship_delivery_grants(
    recipient_person_id,
    status,
    projection_contracts,
    response_contracts,
    valid_from,
    valid_until,
    issuance_provenance
  ) values(
    v_ipr.person_id,
    'active',
    v_projection_contracts,
    v_response_contracts,
    now(),
    p_grant_valid_until,
    p_provenance
  )
  returning id into v_grant_id;

  insert into atlas.relationship_delivery_institution_bindings(
    grant_id,
    organization_id,
    institutional_person_record_id,
    binding_provenance
  ) values(
    v_grant_id,
    v_ipr.organization_id,
    v_ipr.id,
    p_provenance
  );

  v_raw_secret:='rdb1_'||encode(extensions.gen_random_bytes(32),'hex');
  v_secret_hash:=atlas.relationship_delivery_secret_hash_v1(v_raw_secret);

  insert into atlas.relationship_delivery_bootstrap_credentials(
    grant_id,
    secret_hash,
    status,
    issued_at,
    expires_at,
    provenance
  ) values(
    v_grant_id,
    v_secret_hash,
    'active',
    now(),
    v_bootstrap_expires_at,
    p_provenance
  )
  returning id into v_credential_id;

  return jsonb_build_object(
    'grantId',v_grant_id,
    'recipientPersonId',v_ipr.person_id,
    'relationship',jsonb_build_object(
      'kind','institutional_person_record',
      'organizationId',v_ipr.organization_id,
      'institutionalPersonRecordId',v_ipr.id
    ),
    'bootstrapCredentialId',v_credential_id,
    'bootstrapSecret',v_raw_secret,
    'bootstrapExpiresAt',v_bootstrap_expires_at
  );
end;
$function$;

revoke all on function atlas.issue_institutional_relationship_delivery_service_v1(
  uuid,text[],text[],timestamptz,timestamptz,jsonb
) from public,anon,authenticated;
grant execute on function atlas.issue_institutional_relationship_delivery_service_v1(
  uuid,text[],text[],timestamptz,timestamptz,jsonb
) to service_role;

create or replace function atlas.redeem_relationship_delivery_bootstrap_service_v1(
  p_bootstrap_secret text,
  p_session_ttl_seconds integer default 2592000,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,extensions
as $function$
declare
  v_hash text;
  v_credential record;
  v_session_id uuid;
  v_raw_session_token text;
  v_session_hash text;
  v_session_expires_at timestamptz;
  v_relationship jsonb;
begin
  if p_session_ttl_seconds is null
     or p_session_ttl_seconds<300
     or p_session_ttl_seconds>7776000 then
    raise exception 'Relationship Delivery session lifetime must be between 5 minutes and 90 days.'
      using errcode='22023';
  end if;

  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Relationship Delivery session metadata must be an object.'
      using errcode='22023';
  end if;

  v_hash:=atlas.relationship_delivery_secret_hash_v1(p_bootstrap_secret);

  select
    c.id as credential_id,
    c.grant_id,
    c.status as credential_status,
    c.expires_at as credential_expires_at,
    g.status as grant_status,
    g.valid_from,
    g.valid_until
  into v_credential
  from atlas.relationship_delivery_bootstrap_credentials c
  join atlas.relationship_delivery_grants g on g.id=c.grant_id
  where c.secret_hash=v_hash
  for update of c,g;

  if v_credential.credential_id is null
     or v_credential.credential_status<>'active'
     or v_credential.credential_expires_at<=now()
     or v_credential.grant_status<>'active'
     or v_credential.valid_from>now()
     or (v_credential.valid_until is not null and v_credential.valid_until<=now()) then
    raise exception 'Relationship Delivery bootstrap credential is invalid or unavailable.'
      using errcode='42501';
  end if;

  -- Redeeming possession is still contingent on the recipient relationship
  -- remaining valid. The current resolver supports the first typed adapter:
  -- Institutional Person Record.
  v_relationship:=
    atlas.relationship_delivery_binding_context_internal_v1(
      v_credential.grant_id
    );

  v_session_expires_at:=
    least(
      now()+make_interval(secs=>p_session_ttl_seconds),
      coalesce(v_credential.valid_until,'infinity'::timestamptz)
    );

  v_raw_session_token:='rds1_'||encode(extensions.gen_random_bytes(32),'hex');
  v_session_hash:=atlas.relationship_delivery_secret_hash_v1(v_raw_session_token);

  insert into atlas.relationship_delivery_sessions(
    grant_id,
    token_hash,
    status,
    issued_at,
    expires_at,
    metadata
  ) values(
    v_credential.grant_id,
    v_session_hash,
    'active',
    now(),
    v_session_expires_at,
    p_metadata
  )
  returning id into v_session_id;

  update atlas.relationship_delivery_bootstrap_credentials
  set status='redeemed',
      redeemed_at=now()
  where id=v_credential.credential_id;

  return jsonb_build_object(
    'grantId',v_credential.grant_id,
    'sessionId',v_session_id,
    'sessionToken',v_raw_session_token,
    'sessionExpiresAt',v_session_expires_at,
    'relationship',v_relationship
  );
end;
$function$;

revoke all on function atlas.redeem_relationship_delivery_bootstrap_service_v1(
  text,integer,jsonb
) from public,anon,authenticated;
grant execute on function atlas.redeem_relationship_delivery_bootstrap_service_v1(
  text,integer,jsonb
) to service_role;

create or replace function atlas.relationship_delivery_session_context_service_v1(
  p_session_token text
)
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
  select atlas.relationship_delivery_session_context_internal_v1(p_session_token);
$function$;

revoke all on function atlas.relationship_delivery_session_context_service_v1(text)
  from public,anon,authenticated;
grant execute on function atlas.relationship_delivery_session_context_service_v1(text)
  to service_role;

create or replace function atlas.revoke_relationship_delivery_grant_service_v1(
  p_grant_id uuid,
  p_reason text,
  p_provenance jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_grant record;
begin
  if p_reason is null or btrim(p_reason)='' then
    raise exception 'Relationship Delivery revocation requires a reason.'
      using errcode='22023';
  end if;

  if p_provenance is null or jsonb_typeof(p_provenance)<>'object' then
    raise exception 'Relationship Delivery revocation provenance must be an object.'
      using errcode='22023';
  end if;

  select id,status
  into v_grant
  from atlas.relationship_delivery_grants
  where id=p_grant_id
  for update;

  if v_grant.id is null then
    raise exception 'Relationship Delivery grant does not exist.'
      using errcode='P0002';
  end if;

  if v_grant.status='active' then
    update atlas.relationship_delivery_grants
    set status='revoked',
        revoked_at=now(),
        revoke_reason=btrim(p_reason),
        revocation_provenance=p_provenance,
        updated_at=now()
    where id=p_grant_id;

    update atlas.relationship_delivery_bootstrap_credentials
    set status='revoked',
        revoked_at=now()
    where grant_id=p_grant_id
      and status='active';

    update atlas.relationship_delivery_sessions
    set status='revoked',
        revoked_at=now()
    where grant_id=p_grant_id
      and status='active';
  end if;

  return jsonb_build_object(
    'grantId',p_grant_id,
    'status','revoked'
  );
end;
$function$;

revoke all on function atlas.revoke_relationship_delivery_grant_service_v1(
  uuid,text,jsonb
) from public,anon,authenticated;
grant execute on function atlas.revoke_relationship_delivery_grant_service_v1(
  uuid,text,jsonb
) to service_role;

insert into atlas.authenticated_rpc_registry(
  signature,
  classification,
  confidence,
  review_status,
  authenticated_execute_expected,
  security_definer_expected,
  service_execute_expected,
  caller_count,
  policy_reference_count,
  evidence,
  reviewed_at,
  anonymous_execute_expected
) values
(
  'atlas.issue_institutional_relationship_delivery_service_v1(uuid,text[],text[],timestamptz,timestamptz,jsonb)',
  'service_internal','verified','active',
  false,true,true,0,1,
  jsonb_build_object(
    'source','atlas_relationship_delivery_kernel_v1',
    'purpose','Issue one bounded institutional Relationship Delivery grant and one-time bootstrap carrier after upstream issuer authorization.',
    'truthBoundary','Delivery only; does not create Person, institutional relationship, responsibility, Company Work, permission, or Personal Atlas.',
    'directSignedInEndpoint',false
  ),
  now(),false
),
(
  'atlas.redeem_relationship_delivery_bootstrap_service_v1(text,integer,jsonb)',
  'service_internal','verified','active',
  false,true,true,0,1,
  jsonb_build_object(
    'source','atlas_relationship_delivery_kernel_v1',
    'purpose','Exchange a one-time possession credential for a bounded server-side Relationship Delivery session.',
    'truthBoundary','Credential/session transport only; typed recipient relationship is revalidated at redemption.',
    'directSignedInEndpoint',false
  ),
  now(),false
),
(
  'atlas.relationship_delivery_session_context_service_v1(text)',
  'service_internal','verified','active',
  false,true,true,0,1,
  jsonb_build_object(
    'source','atlas_relationship_delivery_kernel_v1',
    'purpose','Resolve an active server-held delivery session to its bounded recipient relationship and named projection/response contracts.',
    'truthBoundary','Read-only delivery context; does not grant source-domain consequence by itself.',
    'directSignedInEndpoint',false
  ),
  now(),false
),
(
  'atlas.revoke_relationship_delivery_grant_service_v1(uuid,text,jsonb)',
  'service_internal','verified','active',
  false,true,true,0,1,
  jsonb_build_object(
    'source','atlas_relationship_delivery_kernel_v1',
    'purpose','Prospectively revoke Relationship Delivery possession without rewriting the underlying Person, relationship, responsibility, or result history.',
    'truthBoundary','Delivery lifecycle only.',
    'directSignedInEndpoint',false
  ),
  now(),false
)
on conflict (signature)
do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  reviewed_at=excluded.reviewed_at,
  anonymous_execute_expected=excluded.anonymous_execute_expected;

insert into atlas.architecture_truth_authorities(
  authority_key,
  domain_key,
  truth_question,
  authority_owner,
  authority_status,
  canonical_relations,
  canonical_functions,
  supporting_relations,
  consumer_surfaces,
  known_competitors,
  source_custody,
  rationale
) values (
  'relationship_delivery_grant',
  'delivery',
  'Which bounded projection and response contracts may this canonical Person receive through this currently valid governed relationship-delivery carrier?',
  'atlas.relationship_delivery_grants',
  'canonical',
  array[
    'atlas.relationship_delivery_grants',
    'atlas.relationship_delivery_institution_bindings',
    'atlas.relationship_delivery_bootstrap_credentials',
    'atlas.relationship_delivery_sessions'
  ],
  array[
    'atlas.issue_institutional_relationship_delivery_service_v1',
    'atlas.redeem_relationship_delivery_bootstrap_service_v1',
    'atlas.relationship_delivery_session_context_service_v1',
    'atlas.revoke_relationship_delivery_grant_service_v1'
  ],
  array[
    'atlas.people',
    'atlas.institutional_person_records'
  ],
  array[
    'future no-login Worker delivery',
    'future no-login Household delivery',
    'friendly relationship-scoped delivery routes'
  ],
  array[
    'friendly URL path treated as authority',
    'auth.users treated as required recipient identity',
    'organization membership treated as required delivery identity',
    'Anna-specific worker-delivery pilot treated as universal kernel',
    'generic external task store'
  ],
  'optical-lift/noel-core-db:supabase/migrations/20260921154500_atlas_relationship_delivery_kernel_v1.sql',
  'Relationship Delivery governs only bounded delivery possession. Source-domain truth, responsibility, completion semantics, and relationship truth remain separately canonical. Typed relationship bindings preserve foreign-key integrity rather than using an unvalidated polymorphic relationship id.'
)
on conflict (authority_key)
do update set
  domain_key=excluded.domain_key,
  truth_question=excluded.truth_question,
  authority_owner=excluded.authority_owner,
  authority_status=excluded.authority_status,
  canonical_relations=excluded.canonical_relations,
  canonical_functions=excluded.canonical_functions,
  supporting_relations=excluded.supporting_relations,
  consumer_surfaces=excluded.consumer_surfaces,
  known_competitors=excluded.known_competitors,
  source_custody=excluded.source_custody,
  rationale=excluded.rationale,
  updated_at=now();

do $security_guard$
declare
  v_sig text;
begin
  if has_table_privilege('anon','atlas.relationship_delivery_grants','SELECT')
     or has_table_privilege('authenticated','atlas.relationship_delivery_grants','SELECT')
     or has_table_privilege('anon','atlas.relationship_delivery_sessions','SELECT')
     or has_table_privilege('authenticated','atlas.relationship_delivery_sessions','SELECT')
     or has_table_privilege('service_role','atlas.relationship_delivery_bootstrap_credentials','SELECT') then
    raise exception 'Relationship Delivery tables must remain behind service-only security-definer contracts.';
  end if;

  foreach v_sig in array array[
    'atlas.issue_institutional_relationship_delivery_service_v1(uuid,text[],text[],timestamptz,timestamptz,jsonb)',
    'atlas.redeem_relationship_delivery_bootstrap_service_v1(text,integer,jsonb)',
    'atlas.relationship_delivery_session_context_service_v1(text)',
    'atlas.revoke_relationship_delivery_grant_service_v1(uuid,text,jsonb)'
  ]
  loop
    if has_function_privilege('anon',v_sig,'EXECUTE')
       or has_function_privilege('authenticated',v_sig,'EXECUTE')
       or not has_function_privilege('service_role',v_sig,'EXECUTE') then
      raise exception 'Relationship Delivery service function privilege is invalid: %',v_sig;
    end if;
  end loop;
end;
$security_guard$;

commit;
