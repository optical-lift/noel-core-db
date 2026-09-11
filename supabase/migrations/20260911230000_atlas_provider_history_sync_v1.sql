begin;

create or replace function atlas.provider_history_sync_context_self_api_v1(
  p_connected_source_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user uuid:=auth.uid();
  v_source atlas.connected_sources%rowtype;
begin
  if v_user is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  select * into v_source
  from atlas.connected_sources
  where id=p_connected_source_id;

  if v_source.id is null or v_source.authorization_state<>'connected' then
    raise exception 'Connected source is unavailable.' using errcode='P0002';
  end if;
  if not (v_source.capabilities @> '{"communicationCapture":true}'::jsonb) then
    raise exception 'Connected source is not authorized for communication capture.' using errcode='42501';
  end if;

  if v_source.custodian_user_id is not null then
    if v_source.custodian_user_id is distinct from v_user then
      raise exception 'Principal source custody required.' using errcode='42501';
    end if;
  elsif v_source.custodian_organization_id is not null then
    if not atlas.organization_connected_source_authorized_self_v1(v_source.custodian_organization_id) then
      raise exception 'Organization provider connection authority required.' using errcode='42501';
    end if;
  else
    raise exception 'Connected source has no valid custody root.' using errcode='23514';
  end if;

  return jsonb_build_object(
    'contractVersion','provider_history_sync_context_v1',
    'connectedSourceId',v_source.id,
    'providerKey',v_source.provider_key,
    'providerAccountKey',v_source.provider_account_key,
    'custodianKind',case when v_source.custodian_user_id is not null then 'human' else 'organization' end,
    'organizationId',v_source.custodian_organization_id,
    'capabilities',v_source.capabilities,
    'lastSyncAt',v_source.last_sync_at,
    'providerContext',jsonb_build_object(
      'parentFacebookPageId',v_source.metadata->>'parentFacebookPageId'
    ),
    'truthBoundary',jsonb_build_object(
      'historicalProviderCoverageMayBeIncomplete',true,
      'historyDoesNotCreateResponseResponsibility',true,
      'providerCursorIsTransportState',true
    )
  );
end;
$function$;
revoke all on function atlas.provider_history_sync_context_self_api_v1(uuid) from public,anon;
grant execute on function atlas.provider_history_sync_context_self_api_v1(uuid) to authenticated;

create or replace function atlas.ingest_provider_history_events_service_v1(
  p_connected_source_id uuid,
  p_events jsonb,
  p_manifest jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_source atlas.connected_sources%rowtype;
  v_receipt jsonb;
  v_manifest jsonb:=coalesce(p_manifest,'{}'::jsonb)||jsonb_build_object(
    'captureKind','provider_history_sync',
    'historicalBackfill',true,
    'responseWorkCreated',false
  );
  v_principal_ingest regprocedure;
begin
  select * into v_source
  from atlas.connected_sources
  where id=p_connected_source_id and authorization_state='connected';

  if v_source.id is null then raise exception 'Connected source is required.' using errcode='42501'; end if;
  if not (v_source.capabilities @> '{"communicationCapture":true}'::jsonb) then
    raise exception 'Connected source is not authorized for communication capture.' using errcode='42501';
  end if;
  if jsonb_typeof(p_events)<>'array' or jsonb_array_length(p_events)<1 then
    raise exception 'Historical provider events must be a non-empty JSON array.' using errcode='22023';
  end if;

  if v_source.custodian_user_id is not null then
    v_principal_ingest:=to_regprocedure('atlas.ingest_principal_communication_events_service_v1(uuid,jsonb,jsonb)');
    if v_principal_ingest is null then
      raise exception 'Principal communication ingest seam is unavailable.' using errcode='55000';
    end if;
    execute format('select %s($1,$2,$3)',v_principal_ingest)
      into v_receipt
      using v_source.id,p_events,v_manifest;
  elsif v_source.custodian_organization_id is not null then
    -- Historical evidence is admitted into the institutional conversation graph,
    -- but deliberately stops at v2 so old messages do not create/touch response cases.
    v_receipt:=atlas.ingest_organization_communication_events_service_v2(
      v_source.id,p_events,v_manifest
    );
  else
    raise exception 'Connected source has no valid custody root.' using errcode='23514';
  end if;

  return coalesce(v_receipt,'{}'::jsonb)||jsonb_build_object(
    'contractVersion','provider_history_ingest_receipt_v1',
    'historicalBackfill',true,
    'responseWorkCreated',false,
    'governingStateChanged',false
  );
end;
$function$;
revoke all on function atlas.ingest_provider_history_events_service_v1(uuid,jsonb,jsonb) from public,anon,authenticated;
grant execute on function atlas.ingest_provider_history_events_service_v1(uuid,jsonb,jsonb) to service_role;

create or replace function public.provider_history_sync_context_self_api_v1(p_connected_source_id uuid)
returns jsonb
language sql
set search_path=pg_catalog,atlas,public
as $function$
  select atlas.provider_history_sync_context_self_api_v1(p_connected_source_id);
$function$;
revoke all on function public.provider_history_sync_context_self_api_v1(uuid) from public,anon;
grant execute on function public.provider_history_sync_context_self_api_v1(uuid) to authenticated;

create or replace function public.ingest_provider_history_events_service_v1(
  p_connected_source_id uuid,
  p_events jsonb,
  p_manifest jsonb default '{}'::jsonb
) returns jsonb
language sql
set search_path=pg_catalog,atlas,public
as $function$
  select atlas.ingest_provider_history_events_service_v1(p_connected_source_id,p_events,p_manifest);
$function$;
revoke all on function public.ingest_provider_history_events_service_v1(uuid,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.ingest_provider_history_events_service_v1(uuid,jsonb,jsonb) to service_role;

create or replace function public.read_connected_source_secret_service_v1(
  p_connected_source_id uuid,
  p_credential_kind text
) returns text
language sql
set search_path=pg_catalog,atlas,public
as $function$
  select atlas.read_connected_source_secret_service_v1(p_connected_source_id,p_credential_kind);
$function$;
revoke all on function public.read_connected_source_secret_service_v1(uuid,text) from public,anon,authenticated;
grant execute on function public.read_connected_source_secret_service_v1(uuid,text) to service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,authenticated_execute_expected,security_definer_expected,service_execute_expected,caller_count,policy_reference_count,evidence,reviewed_at,anonymous_execute_expected
) values (
  'atlas.provider_history_sync_context_self_api_v1(uuid)',
  'app_endpoint','verified','active',true,true,true,0,0,
  jsonb_build_object(
    'source','atlas_provider_history_sync_v1',
    'purpose','Authorize an explicitly requested historical provider communication sync for a source already connected to the signed-in Principal or an organization they are authorized to configure.',
    'boundary','Human custody must match auth.uid(); organization custody reuses organization provider-connection authority. No credential is returned.',
    'truthBoundary','Authorizes transport backfill only. Historical provider coverage may be incomplete and does not create response responsibility.',
    'classificationRuleVersion',3,
    'directSignedInEndpoint',true
  ),now(),false
) on conflict (signature) do update set
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

commit;
