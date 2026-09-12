begin;

create or replace function atlas.record_generic_email_transport_verification_service_v1(
  p_connected_source_id uuid,
  p_imap_ok boolean,
  p_smtp_ok boolean,
  p_details jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_source atlas.connected_sources%rowtype;
  v_verified boolean := coalesce(p_imap_ok, false) and coalesce(p_smtp_ok, false);
  v_state text;
  v_now timestamptz := now();
  v_credential_updated_at text;
begin
  if jsonb_typeof(coalesce(p_details, '{}'::jsonb)) <> 'object' then
    raise exception 'Transport verification details must be a JSON object.' using errcode = '22023';
  end if;

  select *
  into v_source
  from atlas.connected_sources
  where id = p_connected_source_id
    and provider_key = 'imap_smtp_email'
    and custodian_organization_id is not null
    and authorization_state <> 'revoked'
  for update;

  if v_source.id is null then
    raise exception 'Generic institutional email source not found.' using errcode = 'P0002';
  end if;

  v_credential_updated_at := v_source.metadata->>'credentialUpdatedAt';
  v_state := case when v_verified then 'pending' else 'error' end;

  update atlas.connected_sources
  set authorization_state = v_state,
      capabilities = coalesce(capabilities, '{}'::jsonb)
        || jsonb_build_object(
          'communicationCapture', false,
          'communicationSend', false
        ),
      metadata = coalesce(metadata, '{}'::jsonb)
        || jsonb_build_object(
          'lastTransportTestAt', v_now,
          'lastTransportTest', coalesce(p_details, '{}'::jsonb),
          'transportVerification', jsonb_build_object(
            'verified', v_verified,
            'imapOk', coalesce(p_imap_ok, false),
            'smtpOk', coalesce(p_smtp_ok, false),
            'verifiedAt', v_now,
            'credentialUpdatedAt', v_credential_updated_at
          )
        ),
      updated_at = v_now
  where id = v_source.id;

  return jsonb_build_object(
    'contractVersion', 'generic_email_transport_verification_v1',
    'connectedSourceId', v_source.id,
    'authorizationState', v_state,
    'verified', v_verified,
    'imapOk', coalesce(p_imap_ok, false),
    'smtpOk', coalesce(p_smtp_ok, false),
    'communicationCapture', false,
    'communicationSend', false,
    'verifiedAt', v_now
  );
end;
$function$;

comment on function atlas.record_generic_email_transport_verification_service_v1(uuid,boolean,boolean,jsonb) is
  'Records generic IMAP/SMTP authentication verification only. It never authorizes capture or send; successful verification remains pending until a separate owner activation action.';

-- Keep the existing service RPC name compatible, but remove its former implicit activation authority.
create or replace function atlas.record_generic_email_transport_test_service_v1(
  p_connected_source_id uuid,
  p_imap_ok boolean,
  p_smtp_ok boolean,
  p_details jsonb default '{}'::jsonb
)
returns jsonb
language sql
security definer
set search_path = pg_catalog, atlas
as $function$
  select atlas.record_generic_email_transport_verification_service_v1(
    p_connected_source_id,
    p_imap_ok,
    p_smtp_ok,
    p_details
  );
$function$;

comment on function atlas.record_generic_email_transport_test_service_v1(uuid,boolean,boolean,jsonb) is
  'Compatibility alias for verification-only generic IMAP/SMTP transport testing. This function no longer activates communication capture or send.';

create or replace function atlas.activate_generic_email_transport_self_api_v1(
  p_connected_source_id uuid,
  p_enable_capture boolean,
  p_enable_send boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_source atlas.connected_sources%rowtype;
  v_verification jsonb;
  v_current_credential_updated_at text;
  v_verified_credential_updated_at text;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode = '42501';
  end if;

  select *
  into v_source
  from atlas.connected_sources
  where id = p_connected_source_id
    and provider_key = 'imap_smtp_email'
    and custodian_organization_id is not null
    and authorization_state <> 'revoked'
  for update;

  if v_source.id is null then
    raise exception 'Generic institutional email source not found.' using errcode = 'P0002';
  end if;

  if not atlas.is_organization_owner(v_source.custodian_organization_id) then
    raise exception 'Organization owner authority required.' using errcode = '42501';
  end if;

  if not coalesce(p_enable_capture, false) and not coalesce(p_enable_send, false) then
    raise exception 'Activation must explicitly authorize capture, send, or both.' using errcode = '22023';
  end if;

  v_verification := coalesce(v_source.metadata->'transportVerification', '{}'::jsonb);
  v_current_credential_updated_at := v_source.metadata->>'credentialUpdatedAt';
  v_verified_credential_updated_at := v_verification->>'credentialUpdatedAt';

  if not coalesce((v_verification->>'verified')::boolean, false)
     or not coalesce((v_verification->>'imapOk')::boolean, false)
     or not coalesce((v_verification->>'smtpOk')::boolean, false)
     or v_current_credential_updated_at is null
     or v_verified_credential_updated_at is distinct from v_current_credential_updated_at then
    raise exception 'Current mailbox credential has not passed both IMAP and SMTP verification.' using errcode = '55000';
  end if;

  update atlas.connected_sources
  set authorization_state = 'connected',
      capabilities = coalesce(capabilities, '{}'::jsonb)
        || jsonb_build_object(
          'communicationCapture', coalesce(p_enable_capture, false),
          'communicationSend', coalesce(p_enable_send, false)
        ),
      metadata = coalesce(metadata, '{}'::jsonb)
        || jsonb_build_object(
          'transportActivatedAt', now(),
          'transportActivation', jsonb_build_object(
            'activatedByUserId', auth.uid(),
            'communicationCapture', coalesce(p_enable_capture, false),
            'communicationSend', coalesce(p_enable_send, false),
            'verifiedCredentialUpdatedAt', v_verified_credential_updated_at
          )
        ),
      updated_at = now()
  where id = v_source.id;

  return jsonb_build_object(
    'contractVersion', 'generic_email_transport_activation_v1',
    'connectedSourceId', v_source.id,
    'authorizationState', 'connected',
    'communicationCapture', coalesce(p_enable_capture, false),
    'communicationSend', coalesce(p_enable_send, false)
  );
end;
$function$;

comment on function atlas.activate_generic_email_transport_self_api_v1(uuid,boolean,boolean) is
  'Separate organization-owner activation membrane. Requires successful verification of the currently stored credential and explicit capture/send choices.';

create or replace function public.activate_generic_email_transport_self_api_v1(
  p_connected_source_id uuid,
  p_enable_capture boolean,
  p_enable_send boolean
)
returns jsonb
language sql
set search_path = pg_catalog, atlas, public
as $function$
  select atlas.activate_generic_email_transport_self_api_v1(
    p_connected_source_id,
    p_enable_capture,
    p_enable_send
  );
$function$;

revoke all on function atlas.record_generic_email_transport_verification_service_v1(uuid,boolean,boolean,jsonb) from public, anon, authenticated;
revoke all on function atlas.record_generic_email_transport_test_service_v1(uuid,boolean,boolean,jsonb) from public, anon, authenticated;
revoke all on function atlas.activate_generic_email_transport_self_api_v1(uuid,boolean,boolean) from public, anon;
revoke all on function public.activate_generic_email_transport_self_api_v1(uuid,boolean,boolean) from public, anon;

grant execute on function atlas.record_generic_email_transport_verification_service_v1(uuid,boolean,boolean,jsonb) to service_role;
grant execute on function atlas.record_generic_email_transport_test_service_v1(uuid,boolean,boolean,jsonb) to service_role;
grant execute on function atlas.activate_generic_email_transport_self_api_v1(uuid,boolean,boolean) to authenticated, service_role;
grant execute on function public.activate_generic_email_transport_self_api_v1(uuid,boolean,boolean) to authenticated, service_role;

comment on function public.activate_generic_email_transport_self_api_v1(uuid,boolean,boolean) is
  'Browser API membrane for explicit organization-owner activation after current-credential IMAP and SMTP verification. It performs no network I/O itself.';

commit;
