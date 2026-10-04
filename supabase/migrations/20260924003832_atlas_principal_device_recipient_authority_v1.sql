-- Atlas Principal/Device Authority + Recipient-Bound Reveal Carrier v1.
-- No private device key, plaintext record data key, or protected plaintext is stored here.

create table if not exists atlas.principal_cryptographic_devices (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid not null references atlas.principals(id) on delete restrict,
  device_stable_key text not null unique default ('device_' || replace(gen_random_uuid()::text,'-','')),
  display_name text not null,
  device_state text not null default 'pending',
  signing_profile text not null default 'ecdsa_p256_sha256_v1',
  signing_public_jwk jsonb not null,
  signing_fingerprint text not null unique,
  wrapping_profile text not null default 'p256_ecdh_hkdf_sha256_aes256gcm_v1',
  wrapping_public_jwk jsonb not null,
  wrapping_fingerprint text not null unique,
  registration_basis jsonb not null default '{}'::jsonb,
  possession_verified_at timestamptz,
  activated_at timestamptz,
  revoked_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint principal_cryptographic_devices_display_name_v1
    check (btrim(display_name) <> ''),
  constraint principal_cryptographic_devices_state_v1
    check (device_state in ('pending','active','revoked')),
  constraint principal_cryptographic_devices_signing_profile_v1
    check (signing_profile='ecdsa_p256_sha256_v1'),
  constraint principal_cryptographic_devices_wrapping_profile_v1
    check (wrapping_profile='p256_ecdh_hkdf_sha256_aes256gcm_v1'),
  constraint principal_cryptographic_devices_signing_jwk_v1
    check (
      jsonb_typeof(signing_public_jwk)='object'
      and signing_public_jwk->>'kty'='EC'
      and signing_public_jwk->>'crv'='P-256'
      and signing_public_jwk ? 'x'
      and signing_public_jwk ? 'y'
      and not (signing_public_jwk ? 'd')
    ),
  constraint principal_cryptographic_devices_wrapping_jwk_v1
    check (
      jsonb_typeof(wrapping_public_jwk)='object'
      and wrapping_public_jwk->>'kty'='EC'
      and wrapping_public_jwk->>'crv'='P-256'
      and wrapping_public_jwk ? 'x'
      and wrapping_public_jwk ? 'y'
      and not (wrapping_public_jwk ? 'd')
    ),
  constraint principal_cryptographic_devices_fingerprint_v1
    check (
      signing_fingerprint ~ '^[0-9a-f]{64}$'
      and wrapping_fingerprint ~ '^[0-9a-f]{64}$'
    ),
  constraint principal_cryptographic_devices_shape_v1
    check (
      (device_state='pending' and possession_verified_at is null and activated_at is null and revoked_at is null)
      or
      (device_state='active' and possession_verified_at is not null and activated_at is not null and revoked_at is null)
      or
      (device_state='revoked' and revoked_at is not null)
    ),
  constraint principal_cryptographic_devices_registration_basis_v1
    check (jsonb_typeof(registration_basis)='object'),
  constraint principal_cryptographic_devices_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

comment on table atlas.principal_cryptographic_devices is
  'Principal-controlled public cryptographic authority. Stores public signing/wrapping keys only. Device authority is separate from login, standing, and reveal permission.';

create table if not exists atlas.sealed_reality_recipient_key_envelopes (
  id uuid primary key default gen_random_uuid(),
  sealed_reality_handle_id uuid not null
    references atlas.sealed_reality_handles(id) on delete restrict,
  recipient_principal_id uuid not null
    references atlas.principals(id) on delete restrict,
  device_authority_id uuid not null
    references atlas.principal_cryptographic_devices(id) on delete restrict,
  envelope_profile text not null default 'p256_ecdh_hkdf_sha256_aes256gcm_v1',
  ephemeral_public_jwk jsonb not null,
  hkdf_salt bytea not null,
  nonce bytea not null,
  wrapped_data_key bytea not null,
  context_hash text not null,
  envelope_state text not null default 'active',
  provisioned_by_principal_id uuid not null
    references atlas.principals(id) on delete restrict,
  provisioning_basis jsonb not null default '{}'::jsonb,
  revoked_at timestamptz,
  superseded_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sealed_reality_recipient_key_envelopes_profile_v1
    check (envelope_profile='p256_ecdh_hkdf_sha256_aes256gcm_v1'),
  constraint sealed_reality_recipient_key_envelopes_ephemeral_jwk_v1
    check (
      jsonb_typeof(ephemeral_public_jwk)='object'
      and ephemeral_public_jwk->>'kty'='EC'
      and ephemeral_public_jwk->>'crv'='P-256'
      and ephemeral_public_jwk ? 'x'
      and ephemeral_public_jwk ? 'y'
      and not (ephemeral_public_jwk ? 'd')
    ),
  constraint sealed_reality_recipient_key_envelopes_salt_v1
    check (octet_length(hkdf_salt)=32),
  constraint sealed_reality_recipient_key_envelopes_nonce_v1
    check (octet_length(nonce)=12),
  constraint sealed_reality_recipient_key_envelopes_wrapped_key_v1
    check (octet_length(wrapped_data_key)>=48),
  constraint sealed_reality_recipient_key_envelopes_context_hash_v1
    check (context_hash ~ '^[0-9a-f]{64}$'),
  constraint sealed_reality_recipient_key_envelopes_state_v1
    check (envelope_state in ('active','superseded','revoked')),
  constraint sealed_reality_recipient_key_envelopes_shape_v1
    check (
      (envelope_state='active' and revoked_at is null and superseded_at is null)
      or
      (envelope_state='superseded' and superseded_at is not null and revoked_at is null)
      or
      (envelope_state='revoked' and revoked_at is not null)
    ),
  constraint sealed_reality_recipient_key_envelopes_basis_v1
    check (jsonb_typeof(provisioning_basis)='object'),
  constraint sealed_reality_recipient_key_envelopes_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

create unique index if not exists sealed_reality_recipient_key_envelopes_active_uq_v1
  on atlas.sealed_reality_recipient_key_envelopes(
    sealed_reality_handle_id,device_authority_id
  )
  where envelope_state='active';

create index if not exists sealed_reality_recipient_key_envelopes_principal_idx_v1
  on atlas.sealed_reality_recipient_key_envelopes(
    recipient_principal_id,sealed_reality_handle_id,envelope_state
  );

comment on table atlas.sealed_reality_recipient_key_envelopes is
  'Recipient-bound encrypted record data-key envelope. Possession of this row does not establish reveal authority; a lawful one-time Sealed Reality warrant is still required for carrier delivery.';

alter table atlas.principal_cryptographic_devices enable row level security;
alter table atlas.sealed_reality_recipient_key_envelopes enable row level security;

revoke all on table atlas.principal_cryptographic_devices
  from public,anon,authenticated,service_role;
revoke all on table atlas.sealed_reality_recipient_key_envelopes
  from public,anon,authenticated,service_role;

create or replace function atlas.set_principal_device_authority_updated_at_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','atlas'
as $function$
begin
  new.updated_at=now();
  return new;
end
$function$;

drop trigger if exists principal_cryptographic_devices_updated_at_v1
  on atlas.principal_cryptographic_devices;
create trigger principal_cryptographic_devices_updated_at_v1
before update on atlas.principal_cryptographic_devices
for each row execute function atlas.set_principal_device_authority_updated_at_v1();

drop trigger if exists sealed_reality_recipient_key_envelopes_updated_at_v1
  on atlas.sealed_reality_recipient_key_envelopes;
create trigger sealed_reality_recipient_key_envelopes_updated_at_v1
before update on atlas.sealed_reality_recipient_key_envelopes
for each row execute function atlas.set_principal_device_authority_updated_at_v1();

create or replace function atlas.canonical_p256_public_jwk_fingerprint_v1(
  p_jwk jsonb
)
returns text
language plpgsql
immutable
security definer
set search_path to 'pg_catalog','extensions'
as $function$
declare
  v_x text;
  v_y text;
  v_canonical text;
begin
  if jsonb_typeof(p_jwk)<>'object'
     or p_jwk->>'kty'<>'EC'
     or p_jwk->>'crv'<>'P-256'
     or p_jwk ? 'd' then
    raise exception 'Public JWK must be a P-256 EC public key with no private d member.'
      using errcode='22023';
  end if;

  v_x:=p_jwk->>'x';
  v_y:=p_jwk->>'y';

  if v_x !~ '^[A-Za-z0-9_-]{43}$'
     or v_y !~ '^[A-Za-z0-9_-]{43}$' then
    raise exception 'P-256 public JWK coordinates are invalid.'
      using errcode='22023';
  end if;

  v_canonical:='{"crv":"P-256","kty":"EC","x":"'
    ||v_x||'","y":"'||v_y||'"}';

  return encode(extensions.digest(v_canonical,'sha256'),'hex');
end
$function$;

revoke all on function atlas.canonical_p256_public_jwk_fingerprint_v1(jsonb)
  from public,anon,authenticated;
grant execute on function atlas.canonical_p256_public_jwk_fingerprint_v1(jsonb)
  to service_role;

create or replace function atlas.register_principal_cryptographic_device_self_api_v1(
  p_display_name text,
  p_signing_public_jwk jsonb,
  p_wrapping_public_jwk jsonb,
  p_registration_basis jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_principal atlas.principals%rowtype;
  v_device atlas.principal_cryptographic_devices%rowtype;
  v_signing_fingerprint text;
  v_wrapping_fingerprint text;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select * into v_principal
  from atlas.principals p
  where p.user_id=auth.uid()
    and p.status='active'
  order by p.created_at,p.id
  limit 1;

  if v_principal.id is null then
    raise exception 'Active Principal required.' using errcode='42501';
  end if;

  if btrim(coalesce(p_display_name,''))='' then
    raise exception 'Device display name is required.' using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_registration_basis,'{}'::jsonb))<>'object'
     or jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then
    raise exception 'Registration basis and metadata must be JSON objects.'
      using errcode='22023';
  end if;

  v_signing_fingerprint:=atlas.canonical_p256_public_jwk_fingerprint_v1(
    p_signing_public_jwk
  );
  v_wrapping_fingerprint:=atlas.canonical_p256_public_jwk_fingerprint_v1(
    p_wrapping_public_jwk
  );

  if v_signing_fingerprint=v_wrapping_fingerprint then
    raise exception 'Signing and wrapping authorities must use different key pairs.'
      using errcode='22023';
  end if;

  insert into atlas.principal_cryptographic_devices(
    principal_id,display_name,device_state,
    signing_profile,signing_public_jwk,signing_fingerprint,
    wrapping_profile,wrapping_public_jwk,wrapping_fingerprint,
    registration_basis,metadata
  )
  values(
    v_principal.id,btrim(p_display_name),'pending',
    'ecdsa_p256_sha256_v1',p_signing_public_jwk,v_signing_fingerprint,
    'p256_ecdh_hkdf_sha256_aes256gcm_v1',p_wrapping_public_jwk,v_wrapping_fingerprint,
    coalesce(p_registration_basis,'{}'::jsonb),
    coalesce(p_metadata,'{}'::jsonb)
  )
  returning * into v_device;

  return jsonb_build_object(
    'contractVersion','principal_cryptographic_device_v1',
    'deviceAuthorityId',v_device.id,
    'principalId',v_device.principal_id,
    'deviceStableKey',v_device.device_stable_key,
    'displayName',v_device.display_name,
    'deviceState',v_device.device_state,
    'signingProfile',v_device.signing_profile,
    'signingFingerprint',v_device.signing_fingerprint,
    'wrappingProfile',v_device.wrapping_profile,
    'wrappingFingerprint',v_device.wrapping_fingerprint
  );
end
$function$;

create or replace function atlas.principal_cryptographic_devices_self_api_v1()
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_principal_id uuid;
  v_devices jsonb;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select p.id into v_principal_id
  from atlas.principals p
  where p.user_id=auth.uid()
    and p.status='active'
  order by p.created_at,p.id
  limit 1;

  if v_principal_id is null then
    raise exception 'Active Principal required.' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'deviceAuthorityId',d.id,
      'deviceStableKey',d.device_stable_key,
      'displayName',d.display_name,
      'deviceState',d.device_state,
      'signingProfile',d.signing_profile,
      'signingPublicJwk',d.signing_public_jwk,
      'signingFingerprint',d.signing_fingerprint,
      'wrappingProfile',d.wrapping_profile,
      'wrappingPublicJwk',d.wrapping_public_jwk,
      'wrappingFingerprint',d.wrapping_fingerprint,
      'possessionVerifiedAt',d.possession_verified_at,
      'activatedAt',d.activated_at,
      'revokedAt',d.revoked_at
    )
    order by d.created_at,d.id
  ),'[]'::jsonb)
  into v_devices
  from atlas.principal_cryptographic_devices d
  where d.principal_id=v_principal_id;

  return jsonb_build_object(
    'contractVersion','principal_cryptographic_devices_v1',
    'principalId',v_principal_id,
    'devices',v_devices
  );
end
$function$;

create or replace function atlas.activate_principal_cryptographic_device_service_v1(
  p_device_authority_id uuid,
  p_proof_verified_by text,
  p_proof_artifact_hash text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_device atlas.principal_cryptographic_devices%rowtype;
begin
  if btrim(coalesce(p_proof_verified_by,''))=''
     or lower(btrim(coalesce(p_proof_artifact_hash,''))) !~ '^[0-9a-f]{64}$' then
    raise exception 'Verified possession proof identity and artifact hash are required.'
      using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then
    raise exception 'Activation metadata must be a JSON object.'
      using errcode='22023';
  end if;

  select * into v_device
  from atlas.principal_cryptographic_devices d
  where d.id=p_device_authority_id
  for update;

  if v_device.id is null then
    raise exception 'Cryptographic device authority not found.'
      using errcode='P0002';
  end if;

  if v_device.device_state='revoked' then
    raise exception 'Revoked cryptographic device authority cannot be activated.'
      using errcode='55000';
  end if;

  if v_device.device_state='pending' then
    update atlas.principal_cryptographic_devices
    set device_state='active',
        possession_verified_at=now(),
        activated_at=now(),
        metadata=metadata
          || coalesce(p_metadata,'{}'::jsonb)
          || jsonb_build_object(
            'possessionProofVerifiedBy',btrim(p_proof_verified_by),
            'possessionProofArtifactHash',lower(btrim(p_proof_artifact_hash))
          )
    where id=p_device_authority_id
    returning * into v_device;
  end if;

  return jsonb_build_object(
    'contractVersion','principal_cryptographic_device_activation_v1',
    'deviceAuthorityId',v_device.id,
    'principalId',v_device.principal_id,
    'deviceState',v_device.device_state,
    'possessionVerifiedAt',v_device.possession_verified_at,
    'activatedAt',v_device.activated_at
  );
end
$function$;

create or replace function atlas.revoke_principal_cryptographic_device_self_api_v1(
  p_device_authority_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_principal_id uuid;
  v_device atlas.principal_cryptographic_devices%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select p.id into v_principal_id
  from atlas.principals p
  where p.user_id=auth.uid()
    and p.status='active'
  order by p.created_at,p.id
  limit 1;

  if v_principal_id is null then
    raise exception 'Active Principal required.' using errcode='42501';
  end if;

  if btrim(coalesce(p_reason,''))='' then
    raise exception 'Device revocation reason is required.'
      using errcode='22023';
  end if;

  select * into v_device
  from atlas.principal_cryptographic_devices d
  where d.id=p_device_authority_id
    and d.principal_id=v_principal_id
  for update;

  if v_device.id is null then
    raise exception 'Cryptographic device authority not found for current Principal.'
      using errcode='P0002';
  end if;

  if v_device.device_state<>'revoked' then
    update atlas.principal_cryptographic_devices
    set device_state='revoked',
        revoked_at=now(),
        metadata=metadata || jsonb_build_object(
          'revocationReason',btrim(p_reason)
        )
    where id=v_device.id
    returning * into v_device;

    update atlas.sealed_reality_recipient_key_envelopes
    set envelope_state='revoked',
        revoked_at=now(),
        metadata=metadata || jsonb_build_object(
          'revokedByDeviceRevocation',true,
          'deviceRevocationReason',btrim(p_reason)
        )
    where device_authority_id=v_device.id
      and envelope_state='active';
  end if;

  return jsonb_build_object(
    'contractVersion','principal_cryptographic_device_revocation_v1',
    'deviceAuthorityId',v_device.id,
    'principalId',v_device.principal_id,
    'deviceState',v_device.device_state,
    'revokedAt',v_device.revoked_at
  );
end
$function$;

create or replace function atlas.recipient_key_envelope_context_hash_v1(
  p_handle_id uuid,
  p_device_authority_id uuid,
  p_recipient_principal_id uuid
)
returns text
language sql
immutable
security definer
set search_path to 'pg_catalog','extensions'
as $function$
  select encode(
    extensions.digest(
      'sealed_reality_recipient_key_envelope_v1|'
      ||p_handle_id::text||'|'
      ||p_device_authority_id::text||'|'
      ||p_recipient_principal_id::text||'|reveal_to_device',
      'sha256'
    ),
    'hex'
  );
$function$;

revoke all on function atlas.recipient_key_envelope_context_hash_v1(uuid,uuid,uuid)
  from public,anon,authenticated;
grant execute on function atlas.recipient_key_envelope_context_hash_v1(uuid,uuid,uuid)
  to service_role;

create or replace function atlas.record_sealed_reality_recipient_key_envelope_service_v1(
  p_handle_id uuid,
  p_device_authority_id uuid,
  p_provisioned_by_principal_id uuid,
  p_ephemeral_public_jwk jsonb,
  p_hkdf_salt bytea,
  p_nonce bytea,
  p_wrapped_data_key bytea,
  p_context_hash text,
  p_provisioning_basis jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_handle atlas.sealed_reality_handles%rowtype;
  v_device atlas.principal_cryptographic_devices%rowtype;
  v_envelope atlas.sealed_reality_recipient_key_envelopes%rowtype;
  v_expected_hash text;
begin
  select * into v_handle
  from atlas.sealed_reality_handles h
  where h.id=p_handle_id
    and h.handle_state='active';

  if v_handle.id is null then
    raise exception 'Active Sealed Reality handle not found.'
      using errcode='P0002';
  end if;

  select * into v_device
  from atlas.principal_cryptographic_devices d
  where d.id=p_device_authority_id
    and d.device_state='active';

  if v_device.id is null then
    raise exception 'Active recipient device authority not found.'
      using errcode='P0002';
  end if;

  if not exists(
    select 1 from atlas.principals p
    where p.id=p_provisioned_by_principal_id
      and p.status='active'
  ) then
    raise exception 'Active provisioning Principal not found.'
      using errcode='P0002';
  end if;

  perform atlas.canonical_p256_public_jwk_fingerprint_v1(p_ephemeral_public_jwk);

  if octet_length(p_hkdf_salt)<>32
     or octet_length(p_nonce)<>12
     or octet_length(p_wrapped_data_key)<48 then
    raise exception 'Recipient-bound key envelope cryptographic material is malformed.'
      using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_provisioning_basis,'{}'::jsonb))<>'object'
     or jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then
    raise exception 'Provisioning basis and metadata must be JSON objects.'
      using errcode='22023';
  end if;

  v_expected_hash:=atlas.recipient_key_envelope_context_hash_v1(
    p_handle_id,v_device.id,v_device.principal_id
  );

  if lower(btrim(coalesce(p_context_hash,'')))<>v_expected_hash then
    raise exception 'Recipient-bound key envelope context hash does not match Handle/device/Principal.'
      using errcode='22023';
  end if;

  update atlas.sealed_reality_recipient_key_envelopes
  set envelope_state='superseded',
      superseded_at=now(),
      metadata=metadata || jsonb_build_object(
        'supersededBasis','recipient_envelope_reprovisioned'
      )
  where sealed_reality_handle_id=p_handle_id
    and device_authority_id=v_device.id
    and envelope_state='active';

  insert into atlas.sealed_reality_recipient_key_envelopes(
    sealed_reality_handle_id,recipient_principal_id,device_authority_id,
    envelope_profile,ephemeral_public_jwk,hkdf_salt,nonce,wrapped_data_key,
    context_hash,envelope_state,provisioned_by_principal_id,
    provisioning_basis,metadata
  )
  values(
    p_handle_id,v_device.principal_id,v_device.id,
    'p256_ecdh_hkdf_sha256_aes256gcm_v1',
    p_ephemeral_public_jwk,p_hkdf_salt,p_nonce,p_wrapped_data_key,
    v_expected_hash,'active',p_provisioned_by_principal_id,
    coalesce(p_provisioning_basis,'{}'::jsonb),
    coalesce(p_metadata,'{}'::jsonb)
  )
  returning * into v_envelope;

  return jsonb_build_object(
    'contractVersion','sealed_reality_recipient_key_envelope_v1',
    'recipientEnvelopeId',v_envelope.id,
    'handleId',v_envelope.sealed_reality_handle_id,
    'recipientPrincipalId',v_envelope.recipient_principal_id,
    'deviceAuthorityId',v_envelope.device_authority_id,
    'envelopeProfile',v_envelope.envelope_profile,
    'envelopeState',v_envelope.envelope_state,
    'contextHash',v_envelope.context_hash
  );
end
$function$;

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
  v_authorized boolean:=false;
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

  if v_operation in ('read_encrypted_envelope','reveal','reveal_to_device') then
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

    if v_operation='read_encrypted_envelope' then
      return jsonb_build_object(
        'authorized',true,
        'authorityVersion','restricted_personnel_record_v1',
        'authorityBasis',jsonb_build_object(
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

    if v_operation='reveal_to_device' then
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

      return jsonb_build_object(
        'authorized',true,
        'authorityVersion','restricted_personnel_record_v1',
        'authorityBasis',jsonb_build_object(
          'vaultId',v_record.vault_id,
          'vaultSubjectId',v_record.vault_subject_id,
          'recordId',v_record.id,
          'recordClassKey',v_record.record_class_key,
          'purposeKey',v_record.purpose_key,
          'requiredCapability','vault_record_read',
          'deviceAuthorityId',v_device_id,
          'recipientEnvelopeId',v_envelope_id
        ),
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
    end if;

    return jsonb_build_object(
      'authorized',true,
      'authorityVersion','restricted_personnel_record_v1',
      'authorityBasis',jsonb_build_object(
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
    'recipient-bound key envelope delivered to authorized device carrier',
    jsonb_build_object(
      'deviceAuthorityId',v_device.id,
      'recipientEnvelopeId',v_envelope.id
    )
  );

  return jsonb_build_object(
    'contractVersion','principal_device_recipient_envelope_delivery_v1',
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
    'contextHash',v_envelope.context_hash
  );
end
$function$;

revoke all on function atlas.register_principal_cryptographic_device_self_api_v1(
  text,jsonb,jsonb,jsonb,jsonb
) from public,anon,authenticated;
grant execute on function atlas.register_principal_cryptographic_device_self_api_v1(
  text,jsonb,jsonb,jsonb,jsonb
) to authenticated;

revoke all on function atlas.principal_cryptographic_devices_self_api_v1()
  from public,anon,authenticated;
grant execute on function atlas.principal_cryptographic_devices_self_api_v1()
  to authenticated;

revoke all on function atlas.activate_principal_cryptographic_device_service_v1(
  uuid,text,text,jsonb
) from public,anon,authenticated;
grant execute on function atlas.activate_principal_cryptographic_device_service_v1(
  uuid,text,text,jsonb
) to service_role;

revoke all on function atlas.revoke_principal_cryptographic_device_self_api_v1(
  uuid,text
) from public,anon,authenticated;
grant execute on function atlas.revoke_principal_cryptographic_device_self_api_v1(
  uuid,text
) to authenticated;

revoke all on function atlas.record_sealed_reality_recipient_key_envelope_service_v1(
  uuid,uuid,uuid,jsonb,bytea,bytea,bytea,text,jsonb,jsonb
) from public,anon,authenticated;
grant execute on function atlas.record_sealed_reality_recipient_key_envelope_service_v1(
  uuid,uuid,uuid,jsonb,bytea,bytea,bytea,text,jsonb,jsonb
) to service_role;

revoke all on function atlas.fetch_principal_device_recipient_envelope_for_warrant_service_v1(
  text,uuid
) from public,anon,authenticated;
grant execute on function atlas.fetch_principal_device_recipient_envelope_for_warrant_service_v1(
  text,uuid
) to service_role;
