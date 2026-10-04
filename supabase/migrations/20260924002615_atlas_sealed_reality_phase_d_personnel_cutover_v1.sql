-- Atlas Sealed Reality Phase D v1.
-- Cut Restricted Personnel encrypted-record delivery over to the shared execution kernel.
-- Personnel custody, durable entitlements, record lifecycle, assertions, and plaintext
-- decryption remain domain/application-owned.

-- Existing current records become Sealed Reality participants. This is structural
-- registration only; it does not grant any new authority.
insert into atlas.sealed_reality_handles(
  domain_key,
  domain_object_id,
  handle_state,
  registered_by_principal_id,
  metadata
)
select
  'restricted_personnel_record',
  r.id,
  'active',
  r.written_by_principal_id,
  jsonb_build_object(
    'basis','restricted_personnel_phase_d_backfill',
    'sourceRecordId',r.id
  )
from atlas.restricted_vault_records r
where r.record_state='current'
on conflict (domain_key,domain_object_id) do nothing;

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

  if v_operation in ('read_encrypted_envelope','reveal') then
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

    -- Reserved for a later application/KMS plaintext-reveal carrier. Phase D does
    -- not execute this operation; it preserves the authority contract established
    -- in Phase A without pretending ciphertext delivery equals plaintext reveal.
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

create or replace function atlas.store_restricted_vault_record_service_v1(
  p_vault_id uuid,
  p_vault_subject_id uuid,
  p_record_class_key text,
  p_purpose_key text,
  p_written_by_principal_id uuid,
  p_ciphertext bytea,
  p_wrapped_data_key bytea,
  p_content_hash text,
  p_kms_key_version text default null,
  p_encryption_context jsonb default '{}'::jsonb,
  p_retention_until date default null,
  p_supersedes_record_id uuid default null,
  p_reason text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_class text:=lower(btrim(coalesce(p_record_class_key,'')));
  v_purpose text:=lower(btrim(coalesce(p_purpose_key,'')));
  v_vault atlas.restricted_vaults%rowtype;
  v_record_class atlas.restricted_vault_record_classes%rowtype;
  v_record atlas.restricted_vault_records%rowtype;
  v_handle_id uuid;
  v_allowed boolean;
begin
  select * into v_vault
  from atlas.restricted_vaults v
  where v.id=p_vault_id and v.vault_state='active';

  if v_vault.id is null then
    raise exception 'Active restricted vault not found.' using errcode='P0002';
  end if;

  select * into v_record_class
  from atlas.restricted_vault_record_classes c
  where c.record_class_key=v_class and c.class_state='active';

  if v_record_class.record_class_key is null then
    raise exception 'Restricted-vault record class is missing or inactive.'
      using errcode='P0002';
  end if;

  if v_purpose !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$' then
    raise exception 'Purpose key must be normalized.' using errcode='22023';
  end if;

  v_allowed:=atlas.principal_has_restricted_vault_capability_v1(
    p_written_by_principal_id,p_vault_id,'vault_record_write',v_class,v_purpose
  );

  if not v_allowed then
    perform atlas.write_restricted_vault_audit_event_internal_v1(
      p_vault_id,p_written_by_principal_id,'record_write','denied',
      'vault_record_write',p_vault_subject_id,null,null,v_purpose,
      coalesce(nullif(btrim(p_reason),''),'principal lacks record-write capability'),
      jsonb_build_object('recordClassKey',v_class)
    );
    return jsonb_build_object(
      'contractVersion','restricted_vault_record_write_v1',
      'authorized',false,
      'reason','vault_record_write_required'
    );
  end if;

  if not exists(
    select 1 from atlas.restricted_vault_subjects s
    where s.id=p_vault_subject_id
      and s.vault_id=p_vault_id
      and s.subject_state='active'
  ) then
    raise exception 'Active vault subject not found.' using errcode='P0002';
  end if;

  if octet_length(p_ciphertext)<16
     or octet_length(p_wrapped_data_key)<16
     or length(coalesce(p_content_hash,''))<32 then
    raise exception 'Encrypted record envelope is incomplete.'
      using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_encryption_context,'{}'::jsonb))<>'object'
     or jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then
    raise exception 'Encryption context and metadata must be JSON objects.'
      using errcode='22023';
  end if;

  if p_supersedes_record_id is not null
     and not exists(
       select 1 from atlas.restricted_vault_records r
       where r.id=p_supersedes_record_id
         and r.vault_id=p_vault_id
         and r.vault_subject_id=p_vault_subject_id
     ) then
    raise exception 'Superseded record is outside this vault subject.'
      using errcode='22023';
  end if;

  insert into atlas.restricted_vault_records(
    vault_id,vault_subject_id,record_class_key,purpose_key,sensitivity,
    record_state,supersedes_record_id,crypto_profile,kms_key_ref,kms_key_version,
    ciphertext,wrapped_data_key,encryption_context,content_hash,
    content_hash_algorithm,retention_until,metadata,written_by_principal_id
  )
  values(
    p_vault_id,p_vault_subject_id,v_class,v_purpose,
    v_record_class.default_sensitivity,'current',p_supersedes_record_id,
    v_vault.crypto_profile,v_vault.kms_key_ref,nullif(btrim(p_kms_key_version),''),
    p_ciphertext,p_wrapped_data_key,coalesce(p_encryption_context,'{}'::jsonb),
    btrim(p_content_hash),'sha256',p_retention_until,
    coalesce(p_metadata,'{}'::jsonb),p_written_by_principal_id
  )
  returning * into v_record;

  if p_supersedes_record_id is not null then
    update atlas.restricted_vault_records
    set record_state='superseded'
    where id=p_supersedes_record_id and record_state='current';

    update atlas.sealed_reality_handles
    set handle_state='retired',
        updated_at=now(),
        metadata=metadata || jsonb_build_object(
          'retiredBasis','personnel_record_superseded',
          'supersededByRecordId',v_record.id
        )
    where domain_key='restricted_personnel_record'
      and domain_object_id=p_supersedes_record_id
      and handle_state='active';
  end if;

  -- Handle registration is a structural consequence of a lawful record write.
  -- It does not require a second administrative entitlement and grants no access.
  insert into atlas.sealed_reality_handles(
    domain_key,domain_object_id,handle_state,registered_by_principal_id,metadata
  )
  values(
    'restricted_personnel_record',v_record.id,'active',p_written_by_principal_id,
    jsonb_build_object(
      'basis','restricted_personnel_record_write',
      'vaultId',p_vault_id,
      'vaultSubjectId',p_vault_subject_id
    )
  )
  on conflict (domain_key,domain_object_id) do update
  set handle_state='active',
      updated_at=now()
  returning id into v_handle_id;

  perform atlas.write_restricted_vault_audit_event_internal_v1(
    p_vault_id,p_written_by_principal_id,'record_write','completed',
    'vault_record_write',p_vault_subject_id,v_record.id,null,v_purpose,
    coalesce(nullif(btrim(p_reason),''),'encrypted personnel record stored'),
    jsonb_build_object(
      'recordClassKey',v_class,
      'sensitivity',v_record.sensitivity,
      'sealedRealityHandleId',v_handle_id
    )
  );

  return jsonb_build_object(
    'contractVersion','restricted_vault_record_write_v1',
    'authorized',true,
    'recordId',v_record.id,
    'vaultId',v_record.vault_id,
    'vaultSubjectId',v_record.vault_subject_id,
    'recordClassKey',v_record.record_class_key,
    'purposeKey',v_record.purpose_key,
    'sensitivity',v_record.sensitivity,
    'recordState',v_record.record_state,
    'cryptoProfile',v_record.crypto_profile,
    'sealedRealityHandleId',v_handle_id
  );
end
$function$;

create or replace function atlas.read_restricted_vault_record_envelope_service_v1(
  p_record_id uuid,
  p_principal_id uuid,
  p_reason text,
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
  v_request jsonb;
  v_completion jsonb;
  v_token text;
begin
  select * into v_record
  from atlas.restricted_vault_records r
  where r.id=p_record_id;

  if v_record.id is null then
    raise exception 'Restricted-vault record not found.' using errcode='P0002';
  end if;

  if btrim(coalesce(p_reason,''))='' then
    raise exception 'Restricted-vault read reason is required.' using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_context,'{}'::jsonb))<>'object' then
    raise exception 'Read context must be a JSON object.' using errcode='22023';
  end if;

  select h.id into v_handle_id
  from atlas.sealed_reality_handles h
  where h.domain_key='restricted_personnel_record'
    and h.domain_object_id=v_record.id
    and h.handle_state='active';

  if v_handle_id is null then
    raise exception 'Active Sealed Reality handle missing for restricted personnel record.'
      using errcode='55000';
  end if;

  v_request:=atlas.request_sealed_reality_operation_service_v1(
    v_handle_id,
    p_principal_id,
    'read_encrypted_envelope',
    v_record.purpose_key,
    p_reason,
    coalesce(p_context,'{}'::jsonb) || jsonb_build_object(
      'recordClassKey',v_record.record_class_key,
      'vaultId',v_record.vault_id,
      'vaultSubjectId',v_record.vault_subject_id
    )
  );

  if not coalesce((v_request->>'authorized')::boolean,false) then
    return jsonb_build_object(
      'contractVersion','restricted_vault_record_envelope_v1',
      'authorized',false,
      'recordId',v_record.id,
      'reason',coalesce(v_request->>'reason','vault_record_read_required')
    );
  end if;

  if not coalesce((v_request->>'requiresCarrier')::boolean,false)
     or v_request#>>'{carrier,carrierKey}'<>'restricted_vault_envelope_v1'
     or v_request->>'resultPolicy'<>'receipt' then
    raise exception 'Restricted personnel shared carrier contract is invalid.'
      using errcode='55000';
  end if;

  v_token:=v_request->>'warrantToken';

  -- This database service is the encrypted-envelope carrier. It never decrypts
  -- the protected payload. Complete the one-time shared execution before
  -- returning the ciphertext envelope.
  v_completion:=atlas.complete_sealed_reality_operation_service_v1(
    v_token,
    'completed',
    'restricted_vault_envelope_v1',
    jsonb_build_object('delivered',true),
    'restricted-personnel-envelope:'||v_record.id::text,
    jsonb_build_object(
      'recordId',v_record.id,
      'vaultId',v_record.vault_id,
      'delivery','encrypted_envelope'
    )
  );

  if not coalesce((v_completion->>'completed')::boolean,false) then
    raise exception 'Restricted personnel encrypted-envelope delivery did not complete.'
      using errcode='55000';
  end if;

  return jsonb_build_object(
    'contractVersion','restricted_vault_record_envelope_v1',
    'authorized',true,
    'recordId',v_record.id,
    'vaultId',v_record.vault_id,
    'vaultSubjectId',v_record.vault_subject_id,
    'recordClassKey',v_record.record_class_key,
    'purposeKey',v_record.purpose_key,
    'sensitivity',v_record.sensitivity,
    'recordState',v_record.record_state,
    'cryptoProfile',v_record.crypto_profile,
    'kmsKeyRef',v_record.kms_key_ref,
    'kmsKeyVersion',v_record.kms_key_version,
    'ciphertextBase64',encode(v_record.ciphertext,'base64'),
    'wrappedDataKeyBase64',encode(v_record.wrapped_data_key,'base64'),
    'encryptionContext',v_record.encryption_context,
    'contentHash',v_record.content_hash,
    'contentHashAlgorithm',v_record.content_hash_algorithm,
    'retentionUntil',v_record.retention_until,
    'writtenAt',v_record.written_at
  );
end
$function$;

create or replace function atlas.read_restricted_vault_audit_service_v1(
  p_vault_id uuid,
  p_principal_id uuid,
  p_limit integer default 100,
  p_reason text default 'vault audit review'
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_allowed boolean;
  v_events jsonb;
  v_limit integer:=greatest(1,least(coalesce(p_limit,100),500));
begin
  v_allowed:=atlas.principal_has_restricted_vault_capability_v1(
    p_principal_id,p_vault_id,'vault_audit_read',null,null
  );

  perform atlas.write_restricted_vault_audit_event_internal_v1(
    p_vault_id,p_principal_id,'audit_read_attempt',
    case when v_allowed then 'allowed' else 'denied' end,
    'vault_audit_read',null,null,null,null,p_reason,
    jsonb_build_object('limit',v_limit)
  );

  if not v_allowed then
    return jsonb_build_object(
      'contractVersion','restricted_vault_audit_read_v1',
      'authorized',false,
      'reason','vault_audit_read_required',
      'events','[]'::jsonb
    );
  end if;

  -- Preserve historical/personnel-domain audit rows while adding the shared
  -- execution lineage for protected record delivery.
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'auditEventId',q.event_id,
      'principalId',q.principal_id,
      'actionKey',q.action_key,
      'outcome',q.outcome,
      'capabilityKey',q.capability_key,
      'vaultSubjectId',q.vault_subject_id,
      'recordId',q.record_id,
      'assertionId',q.assertion_id,
      'purposeKey',q.purpose_key,
      'reason',q.reason_text,
      'context',q.context,
      'occurredAt',q.occurred_at
    )
    order by q.occurred_at desc,q.event_id
  ),'[]'::jsonb)
  into v_events
  from (
    select
      e.id as event_id,
      e.principal_id,
      e.action_key,
      e.outcome,
      e.capability_key,
      e.vault_subject_id,
      e.record_id,
      e.assertion_id,
      e.purpose_key,
      e.reason_text,
      e.context,
      e.occurred_at
    from atlas.restricted_vault_audit_events e
    where e.vault_id=p_vault_id

    union all

    select
      e.id as event_id,
      e.principal_id,
      case
        when e.event_key='operation_request' then 'record_read_attempt'
        when e.event_key='warrant_issued' then 'record_read_warrant_issued'
        when e.event_key='carrier_completion' then 'record_envelope_delivery'
        when e.event_key='warrant_expired' then 'record_read_warrant_expired'
        else 'sealed_reality_'||e.event_key
      end as action_key,
      e.outcome,
      'vault_record_read'::text as capability_key,
      r.vault_subject_id,
      r.id as record_id,
      null::uuid as assertion_id,
      e.purpose_key,
      e.reason_text,
      e.context || jsonb_build_object(
        'sealedRealityHandleId',h.id,
        'sharedEventId',e.id
      ) as context,
      e.occurred_at
    from atlas.sealed_reality_operation_events e
    join atlas.sealed_reality_handles h
      on h.id=e.sealed_reality_handle_id
     and h.domain_key='restricted_personnel_record'
    join atlas.restricted_vault_records r
      on r.id=h.domain_object_id
    where r.vault_id=p_vault_id

    order by occurred_at desc,event_id
    limit v_limit
  ) q;

  return jsonb_build_object(
    'contractVersion','restricted_vault_audit_read_v1',
    'authorized',true,
    'vaultId',p_vault_id,
    'events',v_events
  );
end
$function$;

revoke all on function atlas.store_restricted_vault_record_service_v1(
  uuid,uuid,text,text,uuid,bytea,bytea,text,text,jsonb,date,uuid,text,jsonb
) from public,anon,authenticated;
grant execute on function atlas.store_restricted_vault_record_service_v1(
  uuid,uuid,text,text,uuid,bytea,bytea,text,text,jsonb,date,uuid,text,jsonb
) to service_role;

revoke all on function atlas.read_restricted_vault_record_envelope_service_v1(
  uuid,uuid,text,jsonb
) from public,anon,authenticated;
grant execute on function atlas.read_restricted_vault_record_envelope_service_v1(
  uuid,uuid,text,jsonb
) to service_role;

revoke all on function atlas.read_restricted_vault_audit_service_v1(
  uuid,uuid,integer,text
) from public,anon,authenticated;
grant execute on function atlas.read_restricted_vault_audit_service_v1(
  uuid,uuid,integer,text
) to service_role;
