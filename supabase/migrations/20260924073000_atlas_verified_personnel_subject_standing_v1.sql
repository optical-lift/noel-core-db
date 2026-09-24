-- Atlas Verified Personnel Subject Standing v1.
-- Establishes a verified Atlas Person <-> canonical Shared Intelligence Person bridge
-- and allows narrowly policy-governed subject authority for reveal_to_device.

create table if not exists atlas.person_canonical_entity_bindings (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null references atlas.people(id) on delete restrict,
  canonical_entity_id uuid not null references local_intel.entities(id) on delete restrict,
  binding_state text not null default 'verified',
  verification_method text not null,
  proof_artifact_hash text not null,
  verification_authority text not null,
  verified_by_principal_id uuid references atlas.principals(id) on delete restrict,
  verified_at timestamptz not null default now(),
  retired_at timestamptz,
  disputed_at timestamptz,
  verification_basis jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint person_canonical_entity_bindings_state_v1
    check (binding_state in ('verified','retired','disputed')),
  constraint person_canonical_entity_bindings_method_v1
    check (verification_method in (
      'claimant_verified',
      'operator_verified',
      'migration_verified',
      'recovery_verified'
    )),
  constraint person_canonical_entity_bindings_hash_v1
    check (proof_artifact_hash ~ '^[0-9a-f]{64}$'),
  constraint person_canonical_entity_bindings_authority_v1
    check (btrim(verification_authority) <> ''),
  constraint person_canonical_entity_bindings_shape_v1
    check (
      (binding_state='verified' and retired_at is null and disputed_at is null)
      or
      (binding_state='retired' and retired_at is not null and disputed_at is null)
      or
      (binding_state='disputed' and disputed_at is not null)
    ),
  constraint person_canonical_entity_bindings_basis_v1
    check (jsonb_typeof(verification_basis)='object'),
  constraint person_canonical_entity_bindings_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

create unique index if not exists person_canonical_entity_bindings_verified_person_uq_v1
  on atlas.person_canonical_entity_bindings(person_id)
  where binding_state='verified';

create unique index if not exists person_canonical_entity_bindings_verified_entity_uq_v1
  on atlas.person_canonical_entity_bindings(canonical_entity_id)
  where binding_state='verified';

comment on table atlas.person_canonical_entity_bindings is
  'Verified identity bridge between Atlas auth-compatible Person and one canonical Shared Intelligence person. Resolver recognition alone is not sufficient to create this binding.';

create table if not exists atlas.restricted_vault_subject_operation_policies (
  record_class_key text not null
    references atlas.restricted_vault_record_classes(record_class_key) on delete restrict,
  operation_key text not null,
  authority_kind text not null default 'verified_subject_standing',
  policy_state text not null default 'active',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(record_class_key,operation_key,authority_kind),
  constraint restricted_vault_subject_operation_policies_operation_v1
    check (operation_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint restricted_vault_subject_operation_policies_authority_v1
    check (authority_kind='verified_subject_standing'),
  constraint restricted_vault_subject_operation_policies_state_v1
    check (policy_state in ('active','retired')),
  constraint restricted_vault_subject_operation_policies_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

insert into atlas.restricted_vault_subject_operation_policies(
  record_class_key,operation_key,authority_kind,policy_state,metadata
)
values
(
  'identity_document',
  'reveal_to_device',
  'verified_subject_standing',
  'active',
  '{"basis":"individually_governed_secret_v1"}'::jsonb
),
(
  'tax_identity',
  'reveal_to_device',
  'verified_subject_standing',
  'active',
  '{"basis":"individually_governed_secret_v1"}'::jsonb
),
(
  'banking_payroll',
  'reveal_to_device',
  'verified_subject_standing',
  'active',
  '{"basis":"individually_governed_secret_v1"}'::jsonb
)
on conflict (record_class_key,operation_key,authority_kind) do update
set policy_state='active',
    metadata=atlas.restricted_vault_subject_operation_policies.metadata || excluded.metadata,
    updated_at=now();

alter table atlas.person_canonical_entity_bindings enable row level security;
alter table atlas.restricted_vault_subject_operation_policies enable row level security;

revoke all on table atlas.person_canonical_entity_bindings
  from public,anon,authenticated,service_role;
revoke all on table atlas.restricted_vault_subject_operation_policies
  from public,anon,authenticated;
grant select on table atlas.restricted_vault_subject_operation_policies to service_role;

create or replace function atlas.set_personnel_subject_standing_updated_at_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','atlas'
as $function$
begin
  new.updated_at=now();
  return new;
end
$function$;

drop trigger if exists person_canonical_entity_bindings_updated_at_v1
  on atlas.person_canonical_entity_bindings;
create trigger person_canonical_entity_bindings_updated_at_v1
before update on atlas.person_canonical_entity_bindings
for each row execute function atlas.set_personnel_subject_standing_updated_at_v1();

drop trigger if exists restricted_vault_subject_operation_policies_updated_at_v1
  on atlas.restricted_vault_subject_operation_policies;
create trigger restricted_vault_subject_operation_policies_updated_at_v1
before update on atlas.restricted_vault_subject_operation_policies
for each row execute function atlas.set_personnel_subject_standing_updated_at_v1();

create or replace function atlas.establish_verified_person_canonical_binding_service_v1(
  p_person_id uuid,
  p_canonical_entity_id uuid,
  p_verification_method text,
  p_proof_artifact_hash text,
  p_verification_authority text,
  p_verified_by_principal_id uuid default null,
  p_verification_basis jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_method text:=lower(btrim(coalesce(p_verification_method,'')));
  v_hash text:=lower(btrim(coalesce(p_proof_artifact_hash,'')));
  v_binding atlas.person_canonical_entity_bindings%rowtype;
  v_conflict atlas.person_canonical_entity_bindings%rowtype;
begin
  if v_method not in (
    'claimant_verified',
    'operator_verified',
    'migration_verified',
    'recovery_verified'
  ) then
    raise exception 'Unsupported verified identity binding method.'
      using errcode='22023';
  end if;

  if v_hash !~ '^[0-9a-f]{64}$'
     or btrim(coalesce(p_verification_authority,''))='' then
    raise exception 'Verified identity binding requires proof artifact hash and verification authority.'
      using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_verification_basis,'{}'::jsonb))<>'object'
     or jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then
    raise exception 'Verification basis and metadata must be JSON objects.'
      using errcode='22023';
  end if;

  if not exists(
    select 1
    from atlas.people p
    where p.id=p_person_id
      and p.status='active'
  ) then
    raise exception 'Active Atlas Person not found.'
      using errcode='P0002';
  end if;

  if not exists(
    select 1
    from local_intel.entities e
    where e.id=p_canonical_entity_id
      and e.entity_type='person'
      and e.status='active'
  ) then
    raise exception 'Active canonical person entity not found.'
      using errcode='P0002';
  end if;

  if p_verified_by_principal_id is not null
     and not exists(
       select 1
       from atlas.principals p
       where p.id=p_verified_by_principal_id
         and p.status='active'
     ) then
    raise exception 'Verifying Principal is not active.'
      using errcode='P0002';
  end if;

  select * into v_binding
  from atlas.person_canonical_entity_bindings b
  where b.person_id=p_person_id
    and b.canonical_entity_id=p_canonical_entity_id
    and b.binding_state='verified'
  limit 1;

  if v_binding.id is not null then
    return jsonb_build_object(
      'contractVersion','verified_person_canonical_binding_v1',
      'idempotentReplay',true,
      'bindingId',v_binding.id,
      'personId',v_binding.person_id,
      'canonicalEntityId',v_binding.canonical_entity_id,
      'bindingState',v_binding.binding_state,
      'verificationMethod',v_binding.verification_method,
      'verifiedAt',v_binding.verified_at
    );
  end if;

  select * into v_conflict
  from atlas.person_canonical_entity_bindings b
  where b.binding_state='verified'
    and (
      b.person_id=p_person_id
      or b.canonical_entity_id=p_canonical_entity_id
    )
  limit 1;

  if v_conflict.id is not null then
    raise exception 'Verified identity binding conflicts with an existing Person/canonical-person binding.'
      using errcode='23505';
  end if;

  insert into atlas.person_canonical_entity_bindings(
    person_id,canonical_entity_id,binding_state,verification_method,
    proof_artifact_hash,verification_authority,verified_by_principal_id,
    verified_at,verification_basis,metadata
  )
  values(
    p_person_id,p_canonical_entity_id,'verified',v_method,
    v_hash,btrim(p_verification_authority),p_verified_by_principal_id,
    now(),coalesce(p_verification_basis,'{}'::jsonb),
    coalesce(p_metadata,'{}'::jsonb)
  )
  returning * into v_binding;

  return jsonb_build_object(
    'contractVersion','verified_person_canonical_binding_v1',
    'idempotentReplay',false,
    'bindingId',v_binding.id,
    'personId',v_binding.person_id,
    'canonicalEntityId',v_binding.canonical_entity_id,
    'bindingState',v_binding.binding_state,
    'verificationMethod',v_binding.verification_method,
    'verifiedAt',v_binding.verified_at
  );
end
$function$;

revoke all on function atlas.establish_verified_person_canonical_binding_service_v1(
  uuid,uuid,text,text,text,uuid,jsonb,jsonb
) from public,anon,authenticated;
grant execute on function atlas.establish_verified_person_canonical_binding_service_v1(
  uuid,uuid,text,text,text,uuid,jsonb,jsonb
) to service_role;

create or replace function atlas.resolve_restricted_vault_subject_standing_internal_v1(
  p_principal_id uuid,
  p_vault_subject_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog','atlas'
as $function$
  select coalesce((
    select jsonb_build_object(
      'hasStanding',true,
      'principalId',p.id,
      'personId',p.person_id,
      'bindingId',b.id,
      'canonicalEntityId',b.canonical_entity_id,
      'vaultSubjectId',s.id,
      'verificationMethod',b.verification_method,
      'verifiedAt',b.verified_at
    )
    from atlas.principals p
    join atlas.people ap
      on ap.id=p.person_id
     and ap.status='active'
    join atlas.person_canonical_entity_bindings b
      on b.person_id=ap.id
     and b.binding_state='verified'
    join atlas.restricted_vault_subjects s
      on s.id=p_vault_subject_id
     and s.subject_state='active'
     and s.canonical_entity_id=b.canonical_entity_id
    where p.id=p_principal_id
      and p.status='active'
    limit 1
  ),jsonb_build_object(
    'hasStanding',false,
    'principalId',p_principal_id,
    'vaultSubjectId',p_vault_subject_id
  ));
$function$;

revoke all on function atlas.resolve_restricted_vault_subject_standing_internal_v1(
  uuid,uuid
) from public,anon,authenticated,service_role;

create or replace function atlas.principal_has_restricted_vault_subject_standing_v1(
  p_principal_id uuid,
  p_vault_subject_id uuid
)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog','atlas'
as $function$
  select coalesce((
    atlas.resolve_restricted_vault_subject_standing_internal_v1(
      p_principal_id,p_vault_subject_id
    )->>'hasStanding'
  )::boolean,false);
$function$;

revoke all on function atlas.principal_has_restricted_vault_subject_standing_v1(
  uuid,uuid
) from public,anon,authenticated;
grant execute on function atlas.principal_has_restricted_vault_subject_standing_v1(
  uuid,uuid
) to service_role;

create or replace function atlas.restricted_vault_subject_operation_allowed_v1(
  p_record_class_key text,
  p_operation_key text
)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog','atlas'
as $function$
  select exists(
    select 1
    from atlas.restricted_vault_subject_operation_policies p
    where p.record_class_key=lower(btrim(p_record_class_key))
      and p.operation_key=lower(btrim(p_operation_key))
      and p.authority_kind='verified_subject_standing'
      and p.policy_state='active'
  );
$function$;

revoke all on function atlas.restricted_vault_subject_operation_allowed_v1(
  text,text
) from public,anon,authenticated;
grant execute on function atlas.restricted_vault_subject_operation_allowed_v1(
  text,text
) to service_role;

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
  v_handle_id uuid;
  v_device_id uuid;
  v_envelope_id uuid;
  v_device_id_text text;
  v_operation text:=lower(btrim(coalesce(p_operation_key,'')));
  v_purpose text:=lower(btrim(coalesce(p_purpose_key,'')));
  v_vault_authorized boolean:=false;
  v_subject_standing jsonb;
  v_subject_authorized boolean:=false;
  v_authority_source text;
begin
  if jsonb_typeof(coalesce(p_context,'{}'::jsonb))<>'object' then
    raise exception 'Sealed Reality authority context must be a JSON object.'
      using errcode='22023';
  end if;

  select * into v_record
  from atlas.restricted_vault_records r
  where r.id=p_domain_object_id;

  if v_record.id is null then
    return jsonb_build_object(
      'authorized',false,
      'authorityVersion','restricted_personnel_record_v1',
      'denialReason','restricted_personnel_record_not_found'
    );
  end if;

  if v_purpose<>v_record.purpose_key then
    return jsonb_build_object(
      'authorized',false,
      'authorityVersion','restricted_personnel_record_v1',
      'denialReason','purpose_mismatch'
    );
  end if;

  if v_operation not in ('read_encrypted_envelope','reveal','reveal_to_device') then
    return jsonb_build_object(
      'authorized',false,
      'authorityVersion','restricted_personnel_record_v1',
      'denialReason','unsupported_operation'
    );
  end if;

  v_vault_authorized:=atlas.principal_has_restricted_vault_capability_v1(
    p_principal_id,
    v_record.vault_id,
    'vault_record_read',
    v_record.record_class_key,
    v_record.purpose_key
  );

  if v_operation='read_encrypted_envelope' then
    if not v_vault_authorized then
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
        'authoritySource','vault_entitlement',
        'vaultId',v_record.vault_id,
        'vaultSubjectId',v_record.vault_subject_id,
        'recordId',v_record.id,
        'recordClassKey',v_record.record_class_key,
        'purposeKey',v_record.purpose_key,
        'requiredCapability','vault_record_read'
      ),
      'requiresCarrier',true,
      'resultPolicy','receipt',
      'revealsPlaintext',false,
      'carrier',jsonb_build_object(
        'carrierKey','restricted_vault_envelope_v1',
        'carrierLocator','atlas://restricted-personnel-record/'||v_record.id::text,
        'carrierVersion','1'
      ),
      'warrantTtlSeconds',120
    );
  end if;

  if v_operation='reveal' then
    if not v_vault_authorized then
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
        'authoritySource','vault_entitlement',
        'vaultId',v_record.vault_id,
        'vaultSubjectId',v_record.vault_subject_id,
        'recordId',v_record.id,
        'recordClassKey',v_record.record_class_key,
        'purposeKey',v_record.purpose_key,
        'requiredCapability','vault_record_read'
      ),
      'requiresCarrier',true,
      'resultPolicy','ephemeral_reveal',
      'revealsPlaintext',true,
      'carrier',jsonb_build_object(
        'carrierKey','restricted_vault_plaintext_reveal_v1',
        'carrierLocator','atlas://restricted-personnel-record/'||v_record.id::text,
        'carrierVersion','1'
      ),
      'warrantTtlSeconds',120
    );
  end if;

  -- reveal_to_device may be authorized either by the existing institutional
  -- vault entitlement or by separately verified human-subject standing when
  -- the record class has an explicit self-governance policy.
  v_subject_standing:=atlas.resolve_restricted_vault_subject_standing_internal_v1(
    p_principal_id,v_record.vault_subject_id
  );

  v_subject_authorized:=
    coalesce((v_subject_standing->>'hasStanding')::boolean,false)
    and atlas.restricted_vault_subject_operation_allowed_v1(
      v_record.record_class_key,'reveal_to_device'
    );

  if not v_vault_authorized and not v_subject_authorized then
    return jsonb_build_object(
      'authorized',false,
      'authorityVersion','restricted_personnel_record_v1',
      'denialReason',
        case
          when coalesce((v_subject_standing->>'hasStanding')::boolean,false)
            then 'subject_standing_operation_not_permitted'
          else 'vault_record_read_or_verified_subject_standing_required'
        end
    );
  end if;

  v_device_id_text:=p_context->>'deviceAuthorityId';

  if v_device_id_text is null
     or v_device_id_text !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    return jsonb_build_object(
      'authorized',false,
      'authorityVersion','restricted_personnel_record_v1',
      'denialReason','active_recipient_device_required'
    );
  end if;

  v_device_id:=v_device_id_text::uuid;

  if not exists(
    select 1
    from atlas.principal_cryptographic_devices d
    where d.id=v_device_id
      and d.principal_id=p_principal_id
      and d.device_state='active'
  ) then
    return jsonb_build_object(
      'authorized',false,
      'authorityVersion','restricted_personnel_record_v1',
      'denialReason','active_recipient_device_required'
    );
  end if;

  select h.id into v_handle_id
  from atlas.sealed_reality_handles h
  where h.domain_key='restricted_personnel_record'
    and h.domain_object_id=v_record.id
    and h.handle_state='active';

  if v_handle_id is null then
    return jsonb_build_object(
      'authorized',false,
      'authorityVersion','restricted_personnel_record_v1',
      'denialReason','sealed_reality_handle_required'
    );
  end if;

  select e.id into v_envelope_id
  from atlas.sealed_reality_recipient_key_envelopes e
  where e.sealed_reality_handle_id=v_handle_id
    and e.recipient_principal_id=p_principal_id
    and e.device_authority_id=v_device_id
    and e.envelope_state='active'
  order by e.created_at desc,e.id
  limit 1;

  if v_envelope_id is null then
    return jsonb_build_object(
      'authorized',false,
      'authorityVersion','restricted_personnel_record_v1',
      'denialReason','recipient_key_envelope_required'
    );
  end if;

  v_authority_source:=
    case when v_subject_authorized
      then 'verified_subject_standing'
      else 'vault_entitlement'
    end;

  return jsonb_build_object(
    'authorized',true,
    'authorityVersion','restricted_personnel_record_v1',
    'authorityBasis',
      jsonb_strip_nulls(jsonb_build_object(
        'authoritySource',v_authority_source,
        'vaultId',v_record.vault_id,
        'vaultSubjectId',v_record.vault_subject_id,
        'recordId',v_record.id,
        'recordClassKey',v_record.record_class_key,
        'purposeKey',v_record.purpose_key,
        'requiredCapability',
          case when v_authority_source='vault_entitlement'
            then 'vault_record_read'
            else null
          end,
        'verifiedPersonBindingId',
          case when v_authority_source='verified_subject_standing'
            then v_subject_standing->>'bindingId'
            else null
          end,
        'canonicalEntityId',
          case when v_authority_source='verified_subject_standing'
            then v_subject_standing->>'canonicalEntityId'
            else null
          end,
        'subjectOperationPolicy',
          case when v_authority_source='verified_subject_standing'
            then 'verified_subject_standing'
            else null
          end,
        'deviceAuthorityId',v_device_id,
        'recipientEnvelopeId',v_envelope_id
      )),
    'requiresCarrier',true,
    'resultPolicy','ephemeral_reveal',
    'revealsPlaintext',true,
    'carrier',jsonb_build_object(
      'carrierKey','principal_device_recipient_v1',
      'carrierLocator','atlas://principal-device-recipient/'||v_envelope_id::text,
      'carrierVersion','1'
    ),
    'warrantTtlSeconds',120
  );
end
$function$;

revoke all on function atlas.resolve_restricted_personnel_record_sealed_authority_internal_v1(
  uuid,uuid,text,text,jsonb
) from public,anon,authenticated,service_role;

create or replace function atlas.fetch_principal_device_recipient_envelope_for_warrant_service_v1(
  p_warrant_token text,
  p_device_authority_id uuid
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
  v_device atlas.principal_cryptographic_devices%rowtype;
  v_envelope atlas.sealed_reality_recipient_key_envelopes%rowtype;
  v_handle atlas.sealed_reality_handles%rowtype;
  v_record atlas.restricted_vault_records%rowtype;
  v_expected_device uuid;
  v_expected_envelope uuid;
begin
  if v_token !~ '^[0-9a-f]{64}$' then
    raise exception 'Sealed Reality warrant token is invalid.'
      using errcode='22023';
  end if;

  v_hash:=extensions.digest(v_token,'sha256');

  select * into v_warrant
  from atlas.sealed_reality_operation_warrants w
  where w.warrant_token_hash=v_hash;

  if v_warrant.id is null then
    raise exception 'Sealed Reality operation warrant not found.'
      using errcode='P0002';
  end if;

  if v_warrant.warrant_state<>'issued'
     or v_warrant.expires_at<=now() then
    raise exception 'Sealed Reality operation warrant is no longer usable.'
      using errcode='22023';
  end if;

  if v_warrant.operation_key<>'reveal_to_device'
     or v_warrant.carrier_key<>'principal_device_recipient_v1'
     or v_warrant.domain_key<>'restricted_personnel_record' then
    raise exception 'Warrant is not a Principal-device recipient reveal warrant.'
      using errcode='42501';
  end if;

  begin
    v_expected_device:=(v_warrant.authority_basis->>'deviceAuthorityId')::uuid;
    v_expected_envelope:=(v_warrant.authority_basis->>'recipientEnvelopeId')::uuid;
  exception
    when others then
      raise exception 'Warrant recipient authority basis is malformed.'
        using errcode='22023';
  end;

  if v_expected_device<>p_device_authority_id then
    raise exception 'Warrant is bound to a different device authority.'
      using errcode='42501';
  end if;

  select * into v_device
  from atlas.principal_cryptographic_devices d
  where d.id=p_device_authority_id
    and d.principal_id=v_warrant.principal_id
    and d.device_state='active';

  if v_device.id is null then
    raise exception 'Active recipient device authority not found for warrant Principal.'
      using errcode='42501';
  end if;

  select * into v_envelope
  from atlas.sealed_reality_recipient_key_envelopes e
  where e.id=v_expected_envelope
    and e.sealed_reality_handle_id=v_warrant.sealed_reality_handle_id
    and e.recipient_principal_id=v_warrant.principal_id
    and e.device_authority_id=v_device.id
    and e.envelope_state='active';

  if v_envelope.id is null then
    raise exception 'Active recipient-bound key envelope not found.'
      using errcode='42501';
  end if;

  select * into v_handle
  from atlas.sealed_reality_handles h
  where h.id=v_warrant.sealed_reality_handle_id
    and h.handle_state='active'
    and h.domain_key='restricted_personnel_record';

  if v_handle.id is null then
    raise exception 'Active restricted-personnel Sealed Reality Handle not found.'
      using errcode='42501';
  end if;

  select * into v_record
  from atlas.restricted_vault_records r
  where r.id=v_handle.domain_object_id;

  if v_record.id is null
     or v_record.purpose_key<>v_warrant.purpose_key then
    raise exception 'Restricted Personnel record no longer matches reveal warrant.'
      using errcode='42501';
  end if;

  update atlas.principal_cryptographic_devices
  set metadata=metadata || jsonb_build_object(
        'lastRecipientEnvelopeFetchAt',now()
      )
  where id=v_device.id;

  perform atlas.write_sealed_reality_operation_event_internal_v1(
    v_warrant.sealed_reality_handle_id,
    v_warrant.principal_id,
    v_warrant.domain_key,
    'recipient_envelope_delivery',
    'allowed',
    v_warrant.operation_key,
    v_warrant.purpose_key,
    v_warrant.id,
    null,
    'recipient-bound key envelope and encrypted record delivered to authorized device carrier',
    jsonb_build_object(
      'deviceAuthorityId',v_device.id,
      'recipientEnvelopeId',v_envelope.id,
      'recordId',v_record.id
    )
  );

  return jsonb_build_object(
    'contractVersion','principal_device_recipient_reveal_bundle_v1',
    'warrantId',v_warrant.id,
    'handleId',v_warrant.sealed_reality_handle_id,
    'principalId',v_warrant.principal_id,
    'deviceAuthorityId',v_device.id,
    'recipientEnvelopeId',v_envelope.id,
    'envelopeProfile',v_envelope.envelope_profile,
    'ephemeralPublicJwk',v_envelope.ephemeral_public_jwk,
    'hkdfSaltBase64',encode(v_envelope.hkdf_salt,'base64'),
    'nonceBase64',encode(v_envelope.nonce,'base64'),
    'wrappedDataKeyBase64',encode(v_envelope.wrapped_data_key,'base64'),
    'contextHash',v_envelope.context_hash,
    'recordEnvelope',jsonb_build_object(
      'recordId',v_record.id,
      'vaultId',v_record.vault_id,
      'vaultSubjectId',v_record.vault_subject_id,
      'recordClassKey',v_record.record_class_key,
      'purposeKey',v_record.purpose_key,
      'sensitivity',v_record.sensitivity,
      'recordState',v_record.record_state,
      'cryptoProfile',v_record.crypto_profile,
      'ciphertextBase64',encode(v_record.ciphertext,'base64'),
      'encryptionContext',v_record.encryption_context,
      'contentHash',v_record.content_hash,
      'contentHashAlgorithm',v_record.content_hash_algorithm,
      'retentionUntil',v_record.retention_until,
      'writtenAt',v_record.written_at
    )
  );
end
$function$;

revoke all on function atlas.fetch_principal_device_recipient_envelope_for_warrant_service_v1(
  text,uuid
) from public,anon,authenticated;
grant execute on function atlas.fetch_principal_device_recipient_envelope_for_warrant_service_v1(
  text,uuid
) to service_role;
