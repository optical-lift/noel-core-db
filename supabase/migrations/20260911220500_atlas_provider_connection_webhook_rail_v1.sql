begin;

create table atlas.provider_connection_sessions (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid not null references auth.users(id) on delete cascade,
  custodian_kind text not null check (custodian_kind in ('human','organization')),
  custodian_user_id uuid references auth.users(id) on delete cascade,
  custodian_organization_id uuid references atlas.organizations(id) on delete cascade,
  provider_key text not null check (btrim(provider_key)<>''),
  state_nonce_digest text not null check (state_nonce_digest ~ '^[0-9a-f]{64}$'),
  pkce_challenge text,
  redirect_uri text,
  requested_scopes text[] not null default '{}'::text[],
  requested_capabilities jsonb not null default '{}'::jsonb check (jsonb_typeof(requested_capabilities)='object'),
  session_state text not null default 'pending' check (session_state in ('pending','identity_verified','connected','failed','expired')),
  provider_account_key text,
  connected_source_id uuid references atlas.connected_sources(id) on delete restrict,
  expires_at timestamptz not null,
  completed_at timestamptz,
  failure_reason text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (((custodian_user_id is not null)::int + (custodian_organization_id is not null)::int)=1),
  check ((custodian_kind='human' and custodian_user_id is not null and custodian_organization_id is null)
      or (custodian_kind='organization' and custodian_user_id is null and custodian_organization_id is not null))
);
create unique index provider_connection_sessions_state_digest_uq on atlas.provider_connection_sessions(state_nonce_digest);
create index provider_connection_sessions_actor_idx on atlas.provider_connection_sessions(actor_user_id,created_at desc);

comment on table atlas.provider_connection_sessions is
'Provider-neutral, short-lived authorization correlation. Stores custody intent and callback evidence only; never OAuth codes, tokens, PKCE verifiers, client secrets, API keys, or webhook secrets.';

create table atlas.provider_webhook_deliveries (
  id uuid primary key default gen_random_uuid(),
  connected_source_id uuid not null references atlas.connected_sources(id) on delete restrict,
  provider_key text not null check (btrim(provider_key)<>''),
  provider_delivery_key text not null check (btrim(provider_delivery_key)<>''),
  payload_sha256 text not null check (payload_sha256 ~ '^[0-9a-f]{64}$'),
  delivery_state text not null default 'received' check (delivery_state in ('received','processed','failed','conflict')),
  attempt_count integer not null default 1 check (attempt_count>0),
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  last_error text,
  ingest_receipt jsonb,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  updated_at timestamptz not null default now(),
  unique(provider_key,provider_delivery_key)
);
create index provider_webhook_deliveries_source_idx on atlas.provider_webhook_deliveries(connected_source_id,received_at desc);
comment on table atlas.provider_webhook_deliveries is
'Idempotent provider webhook receipt. Raw provider secrets are never stored here. Provider adapters verify signatures before creating receipts.';

create or replace function atlas.begin_provider_connection_self_api_v1(
  p_custodian_kind text,
  p_organization_id uuid default null,
  p_provider_key text default null,
  p_requested_scopes text[] default '{}'::text[],
  p_requested_capabilities jsonb default '{}'::jsonb,
  p_state_nonce_digest text default null,
  p_pkce_challenge text default null,
  p_redirect_uri text default null,
  p_expires_in_seconds integer default 600,
  p_metadata jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare
  v_user uuid:=auth.uid(); v_kind text:=lower(btrim(coalesce(p_custodian_kind,'')));
  v_provider text:=lower(btrim(coalesce(p_provider_key,''))); v_digest text:=lower(btrim(coalesce(p_state_nonce_digest,'')));
  v_session atlas.provider_connection_sessions%rowtype; v_expiry integer:=greatest(60,least(coalesce(p_expires_in_seconds,600),1800));
begin
  if v_user is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if v_kind not in ('human','organization') or v_provider='' or v_digest !~ '^[0-9a-f]{64}$' then raise exception 'Valid custody kind, provider, and state digest are required.' using errcode='22023'; end if;
  if jsonb_typeof(coalesce(p_requested_capabilities,'{}'::jsonb))<>'object' or jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then raise exception 'Capabilities and metadata must be JSON objects.' using errcode='22023'; end if;
  if lower(coalesce(p_metadata,'{}'::jsonb)::text) ~ '"(access_token|refresh_token|authorization_code|client_secret|api_key|secret_key|webhook_secret|pkce_verifier)"[[:space:]]*:' then raise exception 'Provider secrets are not allowed in connection metadata.' using errcode='22023'; end if;
  if v_kind='human' then
    if p_organization_id is not null then raise exception 'Human provider connection may not name an organization.' using errcode='22023'; end if;
    if not exists(select 1 from atlas.principals p where p.user_id=v_user and p.status='active') then raise exception 'Active Principal required.' using errcode='42501'; end if;
    insert into atlas.provider_connection_sessions(actor_user_id,custodian_kind,custodian_user_id,provider_key,state_nonce_digest,pkce_challenge,redirect_uri,requested_scopes,requested_capabilities,expires_at,metadata)
    values(v_user,'human',v_user,v_provider,v_digest,nullif(btrim(p_pkce_challenge),''),nullif(btrim(p_redirect_uri),''),coalesce(p_requested_scopes,'{}'::text[]),coalesce(p_requested_capabilities,'{}'::jsonb),now()+make_interval(secs=>v_expiry),coalesce(p_metadata,'{}'::jsonb)) returning * into v_session;
  else
    if p_organization_id is null or not atlas.organization_connected_source_authorized_self_v1(p_organization_id) then raise exception 'Organization provider connection authority required.' using errcode='42501'; end if;
    insert into atlas.provider_connection_sessions(actor_user_id,custodian_kind,custodian_organization_id,provider_key,state_nonce_digest,pkce_challenge,redirect_uri,requested_scopes,requested_capabilities,expires_at,metadata)
    values(v_user,'organization',p_organization_id,v_provider,v_digest,nullif(btrim(p_pkce_challenge),''),nullif(btrim(p_redirect_uri),''),coalesce(p_requested_scopes,'{}'::text[]),coalesce(p_requested_capabilities,'{}'::jsonb),now()+make_interval(secs=>v_expiry),coalesce(p_metadata,'{}'::jsonb)) returning * into v_session;
  end if;
  return jsonb_build_object('contractVersion','provider_connection_session_v1','sessionId',v_session.id,'custodianKind',v_session.custodian_kind,'organizationId',v_session.custodian_organization_id,'providerKey',v_session.provider_key,'sessionState',v_session.session_state,'expiresAt',v_session.expires_at);
end;$function$;
revoke all on function atlas.begin_provider_connection_self_api_v1(text,uuid,text,text[],jsonb,text,text,text,integer,jsonb) from public,anon;
grant execute on function atlas.begin_provider_connection_self_api_v1(text,uuid,text,text[],jsonb,text,text,text,integer,jsonb) to authenticated;

create or replace function atlas.complete_provider_connection_identity_service_v1(
  p_session_id uuid,
  p_provider_account_key text,
  p_display_label text default null,
  p_account_hint text default null,
  p_granted_scopes text[] default '{}'::text[],
  p_capabilities jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_session atlas.provider_connection_sessions%rowtype; v_source atlas.connected_sources%rowtype; v_account text:=btrim(coalesce(p_provider_account_key,''));
begin
  select * into v_session from atlas.provider_connection_sessions where id=p_session_id for update;
  if v_session.id is null then raise exception 'Provider connection session not found.' using errcode='P0002'; end if;
  if v_session.session_state='connected' and v_session.connected_source_id is not null then return jsonb_build_object('contractVersion','provider_connection_identity_v1','sessionId',v_session.id,'connectedSourceId',v_session.connected_source_id,'sessionState','connected','alreadyCompleted',true); end if;
  if v_session.session_state not in ('pending','identity_verified') then raise exception 'Provider connection session is not completable.' using errcode='55000'; end if;
  if now()>v_session.expires_at then update atlas.provider_connection_sessions set session_state='expired',updated_at=now() where id=v_session.id; raise exception 'Provider connection session expired.' using errcode='55000'; end if;
  if v_account='' then raise exception 'Provider account identity is required.' using errcode='22023'; end if;
  if jsonb_typeof(coalesce(p_capabilities,'{}'::jsonb))<>'object' or jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then raise exception 'Capabilities and metadata must be JSON objects.' using errcode='22023'; end if;
  if lower(coalesce(p_metadata,'{}'::jsonb)::text) ~ '"(access_token|refresh_token|authorization_code|client_secret|api_key|secret_key|webhook_secret|pkce_verifier)"[[:space:]]*:' then raise exception 'Provider secrets are not allowed in connection metadata.' using errcode='22023'; end if;

  if v_session.custodian_kind='human' then
    insert into atlas.connected_sources(custodian_user_id,custodian_organization_id,custodian_organization_unit_id,provider_key,provider_account_key,display_label,account_hint,authorization_state,granted_scopes,capabilities,metadata)
    values(v_session.custodian_user_id,null,null,v_session.provider_key,v_account,nullif(btrim(p_display_label),''),nullif(btrim(p_account_hint),''),'pending',coalesce(p_granted_scopes,'{}'::text[]),coalesce(p_capabilities,'{}'::jsonb),jsonb_build_object('connectionSessionId',v_session.id)||coalesce(p_metadata,'{}'::jsonb))
    on conflict (custodian_user_id,provider_key,provider_account_key) where custodian_user_id is not null
    do update set display_label=coalesce(excluded.display_label,atlas.connected_sources.display_label),account_hint=coalesce(excluded.account_hint,atlas.connected_sources.account_hint),authorization_state=case when atlas.connected_sources.authorization_state='revoked' then 'revoked' else 'pending' end,granted_scopes=excluded.granted_scopes,capabilities=atlas.connected_sources.capabilities||excluded.capabilities,metadata=atlas.connected_sources.metadata||excluded.metadata,updated_at=now()
    returning * into v_source;
  else
    insert into atlas.connected_sources(custodian_user_id,custodian_organization_id,custodian_organization_unit_id,provider_key,provider_account_key,display_label,account_hint,authorization_state,granted_scopes,capabilities,metadata)
    values(null,v_session.custodian_organization_id,null,v_session.provider_key,v_account,nullif(btrim(p_display_label),''),nullif(btrim(p_account_hint),''),'pending',coalesce(p_granted_scopes,'{}'::text[]),coalesce(p_capabilities,'{}'::jsonb),jsonb_build_object('connectionSessionId',v_session.id)||coalesce(p_metadata,'{}'::jsonb))
    on conflict (custodian_organization_id,provider_key,provider_account_key) where custodian_organization_id is not null
    do update set display_label=coalesce(excluded.display_label,atlas.connected_sources.display_label),account_hint=coalesce(excluded.account_hint,atlas.connected_sources.account_hint),authorization_state=case when atlas.connected_sources.authorization_state='revoked' then 'revoked' else 'pending' end,granted_scopes=excluded.granted_scopes,capabilities=atlas.connected_sources.capabilities||excluded.capabilities,metadata=atlas.connected_sources.metadata||excluded.metadata,updated_at=now()
    returning * into v_source;
  end if;
  if v_source.authorization_state='revoked' then raise exception 'Revoked source cannot be silently reconnected.' using errcode='55000'; end if;
  update atlas.provider_connection_sessions set session_state='identity_verified',provider_account_key=v_account,connected_source_id=v_source.id,metadata=metadata||coalesce(p_metadata,'{}'::jsonb),updated_at=now() where id=v_session.id;
  return jsonb_build_object('contractVersion','provider_connection_identity_v1','sessionId',v_session.id,'connectedSourceId',v_source.id,'providerKey',v_source.provider_key,'providerAccountKey',v_source.provider_account_key,'authorizationState',v_source.authorization_state,'sessionState','identity_verified');
end;$function$;
revoke all on function atlas.complete_provider_connection_identity_service_v1(uuid,text,text,text,text[],jsonb,jsonb) from public,anon,authenticated;
grant execute on function atlas.complete_provider_connection_identity_service_v1(uuid,text,text,text,text[],jsonb,jsonb) to service_role;

create or replace function atlas.activate_provider_connection_service_v1(
  p_session_id uuid,
  p_required_credential_kind text,
  p_metadata jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_session atlas.provider_connection_sessions%rowtype; v_source atlas.connected_sources%rowtype; v_kind text:=btrim(coalesce(p_required_credential_kind,''));
begin
  select * into v_session from atlas.provider_connection_sessions where id=p_session_id for update;
  if v_session.id is null or v_session.connected_source_id is null then raise exception 'Provider connection identity must be verified first.' using errcode='55000'; end if;
  if v_session.session_state='connected' then return jsonb_build_object('contractVersion','provider_connection_activation_v1','sessionId',v_session.id,'connectedSourceId',v_session.connected_source_id,'sessionState','connected','alreadyActivated',true); end if;
  if v_session.session_state<>'identity_verified' then raise exception 'Provider connection is not ready for activation.' using errcode='55000'; end if;
  if v_kind='' or not exists(select 1 from atlas.connected_source_secret_refs r where r.connected_source_id=v_session.connected_source_id and r.credential_kind=v_kind) then raise exception 'Required provider credential is not in Vault custody.' using errcode='55000'; end if;
  update atlas.connected_sources set authorization_state='connected',revoked_at=null,metadata=metadata||coalesce(p_metadata,'{}'::jsonb),updated_at=now() where id=v_session.connected_source_id and authorization_state in ('pending','reauthorization_required','error') returning * into v_source;
  if v_source.id is null then raise exception 'Connected source cannot be activated from its current state.' using errcode='55000'; end if;
  update atlas.provider_connection_sessions set session_state='connected',completed_at=now(),metadata=metadata||coalesce(p_metadata,'{}'::jsonb),updated_at=now() where id=v_session.id;
  return jsonb_build_object('contractVersion','provider_connection_activation_v1','sessionId',v_session.id,'connectedSourceId',v_source.id,'authorizationState',v_source.authorization_state,'sessionState','connected');
end;$function$;
revoke all on function atlas.activate_provider_connection_service_v1(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function atlas.activate_provider_connection_service_v1(uuid,text,jsonb) to service_role;

create or replace function atlas.record_provider_webhook_delivery_service_v1(
  p_connected_source_id uuid,
  p_provider_key text,
  p_provider_delivery_key text,
  p_payload_sha256 text,
  p_metadata jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_source atlas.connected_sources%rowtype; v_delivery atlas.provider_webhook_deliveries%rowtype; v_provider text:=lower(btrim(coalesce(p_provider_key,''))); v_key text:=btrim(coalesce(p_provider_delivery_key,'')); v_hash text:=lower(btrim(coalesce(p_payload_sha256,'')));
begin
  select * into v_source from atlas.connected_sources where id=p_connected_source_id;
  if v_source.id is null or v_source.authorization_state<>'connected' then raise exception 'Connected source is required.' using errcode='42501'; end if;
  if v_provider='' or v_provider is distinct from v_source.provider_key or v_key='' or v_hash !~ '^[0-9a-f]{64}$' then raise exception 'Webhook source identity is invalid.' using errcode='22023'; end if;
  select * into v_delivery from atlas.provider_webhook_deliveries where provider_key=v_provider and provider_delivery_key=v_key for update;
  if found then
    if v_delivery.connected_source_id is distinct from v_source.id or v_delivery.payload_sha256 is distinct from v_hash then
      update atlas.provider_webhook_deliveries set delivery_state='conflict',attempt_count=attempt_count+1,last_error='provider delivery key replayed with mismatched source or payload hash',updated_at=now() where id=v_delivery.id returning * into v_delivery;
      return jsonb_build_object('contractVersion','provider_webhook_delivery_v1','deliveryId',v_delivery.id,'state','conflict','shouldProcess',false,'attemptCount',v_delivery.attempt_count);
    end if;
    update atlas.provider_webhook_deliveries set attempt_count=attempt_count+1,updated_at=now() where id=v_delivery.id returning * into v_delivery;
    return jsonb_build_object('contractVersion','provider_webhook_delivery_v1','deliveryId',v_delivery.id,'state',v_delivery.delivery_state,'shouldProcess',v_delivery.delivery_state in ('received','failed'),'attemptCount',v_delivery.attempt_count);
  end if;
  insert into atlas.provider_webhook_deliveries(connected_source_id,provider_key,provider_delivery_key,payload_sha256,metadata)
  values(v_source.id,v_provider,v_key,v_hash,coalesce(p_metadata,'{}'::jsonb)) returning * into v_delivery;
  return jsonb_build_object('contractVersion','provider_webhook_delivery_v1','deliveryId',v_delivery.id,'state','received','shouldProcess',true,'attemptCount',1);
end;$function$;
revoke all on function atlas.record_provider_webhook_delivery_service_v1(uuid,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function atlas.record_provider_webhook_delivery_service_v1(uuid,text,text,text,jsonb) to service_role;

create or replace function atlas.ingest_provider_webhook_events_service_v1(
  p_provider_webhook_delivery_id uuid,
  p_events jsonb,
  p_manifest jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_delivery atlas.provider_webhook_deliveries%rowtype; v_source atlas.connected_sources%rowtype; v_receipt jsonb;
begin
  select * into v_delivery from atlas.provider_webhook_deliveries where id=p_provider_webhook_delivery_id for update;
  if v_delivery.id is null then raise exception 'Provider webhook delivery not found.' using errcode='P0002'; end if;
  if v_delivery.delivery_state='processed' then return coalesce(v_delivery.ingest_receipt,'{}'::jsonb)||jsonb_build_object('webhookDeliveryId',v_delivery.id,'alreadyProcessed',true); end if;
  if v_delivery.delivery_state='conflict' then raise exception 'Conflicted provider delivery cannot be ingested.' using errcode='55000'; end if;
  select * into v_source from atlas.connected_sources where id=v_delivery.connected_source_id and authorization_state='connected';
  if v_source.id is null then raise exception 'Webhook source is not connected.' using errcode='42501'; end if;
  if v_source.custodian_user_id is not null then
    v_receipt:=atlas.ingest_principal_communication_events_service_v1(v_source.id,p_events,coalesce(p_manifest,'{}'::jsonb)||jsonb_build_object('providerWebhookDeliveryId',v_delivery.id));
  elsif v_source.custodian_organization_id is not null then
    v_receipt:=atlas.ingest_organization_communication_events_service_v3(v_source.id,p_events,coalesce(p_manifest,'{}'::jsonb)||jsonb_build_object('providerWebhookDeliveryId',v_delivery.id));
  else
    raise exception 'Connected source has no valid custody root.' using errcode='23514';
  end if;
  update atlas.provider_webhook_deliveries set delivery_state='processed',processed_at=now(),last_error=null,ingest_receipt=v_receipt,updated_at=now() where id=v_delivery.id;
  return v_receipt||jsonb_build_object('contractVersion','provider_webhook_ingest_v1','webhookDeliveryId',v_delivery.id,'alreadyProcessed',false);
exception when others then
  update atlas.provider_webhook_deliveries set delivery_state=case when delivery_state='conflict' then 'conflict' else 'failed' end,last_error=left(sqlerrm,1000),updated_at=now() where id=p_provider_webhook_delivery_id;
  raise;
end;$function$;
revoke all on function atlas.ingest_provider_webhook_events_service_v1(uuid,jsonb,jsonb) from public,anon,authenticated;
grant execute on function atlas.ingest_provider_webhook_events_service_v1(uuid,jsonb,jsonb) to service_role;

create or replace function public.begin_provider_connection_self_api_v1(
  p_custodian_kind text,p_organization_id uuid default null,p_provider_key text default null,p_requested_scopes text[] default '{}'::text[],p_requested_capabilities jsonb default '{}'::jsonb,p_state_nonce_digest text default null,p_pkce_challenge text default null,p_redirect_uri text default null,p_expires_in_seconds integer default 600,p_metadata jsonb default '{}'::jsonb
) returns jsonb language sql set search_path=pg_catalog,atlas,public as $function$
  select atlas.begin_provider_connection_self_api_v1(p_custodian_kind,p_organization_id,p_provider_key,p_requested_scopes,p_requested_capabilities,p_state_nonce_digest,p_pkce_challenge,p_redirect_uri,p_expires_in_seconds,p_metadata);
+$function$;
revoke all on function public.begin_provider_connection_self_api_v1(text,uuid,text,text[],jsonb,text,text,text,integer,jsonb) from public,anon;
grant execute on function public.begin_provider_connection_self_api_v1(text,uuid,text,text[],jsonb,text,text,text,integer,jsonb) to authenticated;

create or replace function public.complete_provider_connection_identity_service_v1(p_session_id uuid,p_provider_account_key text,p_display_label text default null,p_account_hint text default null,p_granted_scopes text[] default '{}'::text[],p_capabilities jsonb default '{}'::jsonb,p_metadata jsonb default '{}'::jsonb)
returns jsonb language sql set search_path=pg_catalog,atlas,public as $function$ select atlas.complete_provider_connection_identity_service_v1(p_session_id,p_provider_account_key,p_display_label,p_account_hint,p_granted_scopes,p_capabilities,p_metadata); $function$;
revoke all on function public.complete_provider_connection_identity_service_v1(uuid,text,text,text,text[],jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.complete_provider_connection_identity_service_v1(uuid,text,text,text,text[],jsonb,jsonb) to service_role;

create or replace function public.activate_provider_connection_service_v1(p_session_id uuid,p_required_credential_kind text,p_metadata jsonb default '{}'::jsonb)
returns jsonb language sql set search_path=pg_catalog,atlas,public as $function$ select atlas.activate_provider_connection_service_v1(p_session_id,p_required_credential_kind,p_metadata); $function$;
revoke all on function public.activate_provider_connection_service_v1(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.activate_provider_connection_service_v1(uuid,text,jsonb) to service_role;

create or replace function public.record_provider_webhook_delivery_service_v1(p_connected_source_id uuid,p_provider_key text,p_provider_delivery_key text,p_payload_sha256 text,p_metadata jsonb default '{}'::jsonb)
returns jsonb language sql set search_path=pg_catalog,atlas,public as $function$ select atlas.record_provider_webhook_delivery_service_v1(p_connected_source_id,p_provider_key,p_provider_delivery_key,p_payload_sha256,p_metadata); $function$;
revoke all on function public.record_provider_webhook_delivery_service_v1(uuid,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.record_provider_webhook_delivery_service_v1(uuid,text,text,text,jsonb) to service_role;

create or replace function public.ingest_provider_webhook_events_service_v1(p_provider_webhook_delivery_id uuid,p_events jsonb,p_manifest jsonb default '{}'::jsonb)
returns jsonb language sql set search_path=pg_catalog,atlas,public as $function$ select atlas.ingest_provider_webhook_events_service_v1(p_provider_webhook_delivery_id,p_events,p_manifest); $function$;
revoke all on function public.ingest_provider_webhook_events_service_v1(uuid,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.ingest_provider_webhook_events_service_v1(uuid,jsonb,jsonb) to service_role;

revoke all on table atlas.provider_connection_sessions from public,anon,authenticated;
revoke all on table atlas.provider_webhook_deliveries from public,anon,authenticated;
alter table atlas.provider_connection_sessions enable row level security;
alter table atlas.provider_webhook_deliveries enable row level security;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,authenticated_execute_expected,security_definer_expected,service_execute_expected,caller_count,policy_reference_count,evidence,reviewed_at,anonymous_execute_expected
) values (
  'atlas.begin_provider_connection_self_api_v1(text, uuid, text, text[], jsonb, text, text, text, integer, jsonb)',
  'app_endpoint','verified','active',true,true,true,0,0,
  jsonb_build_object('source','atlas_provider_connection_webhook_rail_v1','purpose','Begin a short-lived provider authorization session for either the signed-in Principal or an organization they are authorized to connect.','boundary','SECURITY DEFINER requires auth.uid(); human sessions require active Principal custody; organization sessions reuse organization provider connection authority. Stores only state digest and PKCE challenge, never raw OAuth secrets.','truthBoundary','Begins transport authorization only; creates no Connected Source, communication evidence, task, responsibility, or business truth.','classificationRuleVersion',3,'directSignedInEndpoint',true),now(),false
) on conflict (signature) do update set classification=excluded.classification,confidence=excluded.confidence,review_status=excluded.review_status,authenticated_execute_expected=excluded.authenticated_execute_expected,security_definer_expected=excluded.security_definer_expected,service_execute_expected=excluded.service_execute_expected,caller_count=excluded.caller_count,policy_reference_count=excluded.policy_reference_count,evidence=excluded.evidence,reviewed_at=excluded.reviewed_at,anonymous_execute_expected=excluded.anonymous_execute_expected;

commit;
