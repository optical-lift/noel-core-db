begin;

do $validation$
declare
  v_result jsonb;
  v_visible integer;
begin
  perform set_config('request.jwt.claim.sub','f6100000-0000-4000-8000-000000000001',true);

  if not atlas.connected_source_observe_authorized_self_v1(
    'f6130000-0000-4000-8000-000000000001'::uuid
  ) then
    raise exception 'Organization owner should be observation-authorized.';
  end if;

  v_result := public.prepare_source_observation_self_api_v1(
    'f6130000-0000-4000-8000-000000000001'::uuid,
    'flowerbuyer',
    'browserObservation'
  );

  if v_result->>'sourceId' <> 'f6130000-0000-4000-8000-000000000001'
     or v_result->>'providerKey' <> 'flowerbuyer'
     or v_result->>'effectAuthority' <> 'observe_only' then
    raise exception 'Owner preparation returned unexpected context: %',v_result;
  end if;

  if v_result ? 'secret'
     or v_result ? 'credential'
     or v_result ? 'vaultSecretId'
     or v_result ? 'storageState' then
    raise exception 'Observation preparation exposed credential material: %',v_result;
  end if;

  perform set_config('request.jwt.claim.sub','f6100000-0000-4000-8000-000000000002',true);

  select count(*) into v_visible
  from atlas.connected_sources_self_api_v1()
  where source_id='f6130000-0000-4000-8000-000000000001'::uuid;

  if v_visible<>1 then
    raise exception 'Ordinary Organization member should still see Connected Source status.';
  end if;

  if atlas.connected_source_observe_authorized_self_v1(
    'f6130000-0000-4000-8000-000000000001'::uuid
  ) then
    raise exception 'Ordinary Organization membership must not imply credential-use authority.';
  end if;

  begin
    perform public.prepare_source_observation_self_api_v1(
      'f6130000-0000-4000-8000-000000000001'::uuid,
      'flowerbuyer',
      'browserObservation'
    );
    raise exception 'Ordinary Organization member prepared a credential-using observation.';
  exception when sqlstate '42501' then
    null;
  end;

  perform set_config('request.jwt.claim.sub','f6100000-0000-4000-8000-000000000003',true);

  if not atlas.connected_source_observe_authorized_self_v1(
    'f6130000-0000-4000-8000-000000000001'::uuid
  ) then
    raise exception 'Active setup_actor should retain current Connected Source setup/observation authority.';
  end if;

  perform set_config('request.jwt.claim.sub','f6100000-0000-4000-8000-000000000004',true);

  if atlas.connected_source_observe_authorized_self_v1(
    'f6130000-0000-4000-8000-000000000001'::uuid
  ) then
    raise exception 'Unrelated authenticated user observed an Organization source.';
  end if;

  perform set_config('request.jwt.claim.sub','f6100000-0000-4000-8000-000000000001',true);

  if not atlas.connected_source_observe_authorized_self_v1(
    'f6130000-0000-4000-8000-000000000004'::uuid
  ) then
    raise exception 'Human custodian should be able to observe own Connected Source.';
  end if;

  begin
    perform public.prepare_source_observation_self_api_v1(
      'f6130000-0000-4000-8000-000000000001'::uuid,
      'dvflora',
      'browserObservation'
    );
    raise exception 'Provider mismatch did not fail closed.';
  exception when sqlstate '22023' then
    null;
  end;

  begin
    perform public.prepare_source_observation_self_api_v1(
      'f6130000-0000-4000-8000-000000000002'::uuid,
      'vendor_no_capability',
      'browserObservation'
    );
    raise exception 'Missing browser observation capability did not fail closed.';
  exception when sqlstate '55000' then
    null;
  end;

  if atlas.connected_source_observe_authorized_self_v1(
    'f6130000-0000-4000-8000-000000000003'::uuid
  ) then
    raise exception 'Reauthorization-required source remained observation-usable.';
  end if;

  begin
    perform public.prepare_source_observation_self_api_v1(
      'f6130000-0000-4000-8000-000000000003'::uuid,
      'vendor_reauth',
      'browserObservation'
    );
    raise exception 'Reauthorization-required source prepared an observation.';
  exception when sqlstate '42501' then
    null;
  end;
end;
$validation$;

do $privileges$
begin
  if to_regprocedure('public.prepare_source_observation_self_api_v1(uuid,text,text)') is null
     or to_regprocedure('public.organization_source_authorized_self_api_v1(uuid)') is null
     or to_regprocedure('public.register_organization_source_self_api_v1(uuid,text,text,text,text,text,text[],jsonb,jsonb)') is null
     or to_regprocedure('public.transition_organization_source_self_api_v1(uuid,text,text[],jsonb,jsonb)') is null
     or to_regprocedure('public.update_organization_source_sync_self_api_v1(uuid,timestamptz,jsonb)') is null
     or to_regprocedure('public.store_source_secret_service_v1(uuid,text,text,text)') is null
     or to_regprocedure('public.read_source_secret_service_v1(uuid,text)') is null
     or to_regprocedure('public.delete_source_secret_service_v1(uuid,text)') is null
     or to_regprocedure('public.record_source_observation_batch_service_v1(uuid,text,jsonb,timestamptz,jsonb)') is null
     or to_regprocedure('public.bind_source_org_unit_service_v1(uuid,uuid)') is null then
    raise exception 'Expected stable public Connected Source RPC wrappers are missing.';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.begin_source_connection_self_api_v1(text,uuid,text,text[],jsonb,text,text,text,integer,jsonb)',
    'EXECUTE'
  ) then
    raise exception 'Authenticated role cannot begin a governed source connection.';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.complete_source_connection_identity_service_v1(uuid,text,text,text,text[],jsonb,jsonb)',
    'EXECUTE'
  ) or has_function_privilege(
    'authenticated',
    'public.activate_source_connection_service_v1(uuid,text,jsonb)',
    'EXECUTE'
  ) then
    raise exception 'Authenticated role can bypass service-owned source completion/activation.';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.prepare_source_observation_self_api_v1(uuid,text,text)',
    'EXECUTE'
  ) then
    raise exception 'Authenticated role cannot execute observation preparation wrapper.';
  end if;

  if has_function_privilege(
    'anon',
    'public.prepare_source_observation_self_api_v1(uuid,text,text)',
    'EXECUTE'
  ) then
    raise exception 'Anonymous role can execute observation preparation wrapper.';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.read_source_secret_service_v1(uuid,text)',
    'EXECUTE'
  ) then
    raise exception 'Authenticated role can read reusable provider credentials.';
  end if;

  if not has_function_privilege(
    'service_role',
    'public.read_source_secret_service_v1(uuid,text)',
    'EXECUTE'
  ) then
    raise exception 'Service role cannot use the source-secret transport wrapper.';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.record_source_observation_batch_service_v1(uuid,text,jsonb,timestamptz,jsonb)',
    'EXECUTE'
  ) then
    raise exception 'Authenticated role can bypass service-owned observation custody.';
  end if;

  if not has_function_privilege(
    'service_role',
    'public.record_source_observation_batch_service_v1(uuid,text,jsonb,timestamptz,jsonb)',
    'EXECUTE'
  ) then
    raise exception 'Service role cannot use observation custody wrapper.';
  end if;
end;
$privileges$;

do $service_path$
declare
  v_result jsonb;
  v_count integer;
begin
  v_result := public.record_source_observation_batch_service_v1(
    'f6130000-0000-4000-8000-000000000001'::uuid,
    'supplier.offer',
    jsonb_build_array(
      jsonb_build_object(
        'key','fixture-offer-1',
        'providerCreatedAt',null,
        'payload',jsonb_build_object(
          'product','Red rose',
          'lengthCm',50,
          'price',0.75,
          'currency','USD'
        )
      )
    ),
    now(),
    jsonb_build_object(
      'acquisitionMethod','browser_session',
      'effectAuthority','observe_only',
      'validationFixture',true
    )
  );

  if (v_result->>'recordCount')::integer<>1 then
    raise exception 'Observation wrapper did not preserve one provider record: %',v_result;
  end if;

  select count(*) into v_count
  from atlas.connected_source_observations
  where connected_source_id='f6130000-0000-4000-8000-000000000001'::uuid
    and provider_object_kind='supplier.offer'
    and provider_object_key='fixture-offer-1';

  if v_count<>1 then
    raise exception 'Provider observation was not preserved.';
  end if;
end;
$service_path$;


do $connection_ceremony$
declare
  v_begin jsonb;
  v_identity jsonb;
  v_activation jsonb;
  v_session uuid;
  v_source uuid;
  v_state text;
begin
  perform set_config('request.jwt.claim.sub','f6100000-0000-4000-8000-000000000001',true);

  v_begin := public.begin_source_connection_self_api_v1(
    'organization',
    'f6110000-0000-4000-8000-000000000001'::uuid,
    'browser_fixture',
    '{}'::text[],
    '{"browserObservation":true}'::jsonb,
    repeat('a',64),
    null,
    'https://atlas.example.invalid/connect/source/browser_fixture',
    600,
    '{"connectionMethod":"browser_session","validationFixture":true}'::jsonb
  );

  v_session := (v_begin->>'sessionId')::uuid;
  if v_session is null or v_begin->>'sessionState'<>'pending' then
    raise exception 'Browser source connection did not begin in pending state: %',v_begin;
  end if;

  v_identity := public.complete_source_connection_identity_service_v1(
    v_session,
    'account_sha256:fixture',
    'Browser fixture',
    '…ture',
    '{}'::text[],
    '{"browserObservation":true}'::jsonb,
    '{"identityBasis":"authenticated_login_identifier_digest","validationFixture":true}'::jsonb
  );

  v_source := (v_identity->>'connectedSourceId')::uuid;
  if v_source is null or v_identity->>'authorizationState'<>'pending' then
    raise exception 'Browser source identity completion did not remain pending before credential custody: %',v_identity;
  end if;

  begin
    perform public.activate_source_connection_service_v1(
      v_session,
      'browser_storage_state_v1',
      '{"validationFixture":true}'::jsonb
    );
    raise exception 'Source activated before browser session entered secret custody.';
  exception when sqlstate '55000' then
    null;
  end;

  perform public.store_source_secret_service_v1(
    v_source,
    'browser_storage_state_v1',
    '{"cookies":[],"origins":[]}',
    'Validation browser storage state'
  );

  v_activation := public.activate_source_connection_service_v1(
    v_session,
    'browser_storage_state_v1',
    '{"connectionMethod":"browser_session","validationFixture":true}'::jsonb
  );

  select authorization_state into v_state
  from atlas.connected_sources
  where id=v_source;

  if v_activation->>'sessionState'<>'connected'
     or v_activation->>'authorizationState'<>'connected'
     or v_state<>'connected' then
    raise exception 'Credential-custodied browser source did not activate: %',v_activation;
  end if;

  if exists(
    select 1
    from atlas.provider_connection_sessions
    where id=v_session
      and lower(metadata::text) ~ '"(password|browser_storage_state|cookie|secret)"[[:space:]]*:'
  ) then
    raise exception 'Reusable browser credential leaked into provider connection session metadata.';
  end if;
end;
$connection_ceremony$;

rollback;
