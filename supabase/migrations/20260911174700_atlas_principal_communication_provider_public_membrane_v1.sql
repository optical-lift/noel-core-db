begin;

-- PostgREST public-schema wrappers. Authority remains in atlas.*; these wrappers
-- expose only the deliberately granted client/service membranes.
create or replace function public.upsert_principal_communication_endpoint_self_api_v1(
  p_endpoint_kind text,
  p_address text,
  p_display_name text default null,
  p_metadata jsonb default '{}'::jsonb
) returns jsonb language sql set search_path=pg_catalog,atlas,public as $function$
  select atlas.upsert_principal_communication_endpoint_self_api_v1(p_endpoint_kind,p_address,p_display_name,p_metadata);
$function$;
revoke all on function public.upsert_principal_communication_endpoint_self_api_v1(text,text,text,jsonb) from public,anon;
grant execute on function public.upsert_principal_communication_endpoint_self_api_v1(text,text,text,jsonb) to authenticated;

create or replace function public.principal_communication_endpoints_self_api_v1()
returns table(
  communication_endpoint_id uuid,principal_id uuid,endpoint_kind text,address text,address_normalized text,display_name text,endpoint_state text,
  connected_source_id uuid,provider_key text,provider_account_key text,authorization_state text,binding_role text,binding_state text,source_capabilities jsonb,last_sync_at timestamptz
) language sql stable set search_path=pg_catalog,atlas,public as $function$
  select * from atlas.principal_communication_endpoints_self_api_v1();
$function$;
revoke all on function public.principal_communication_endpoints_self_api_v1() from public,anon;
grant execute on function public.principal_communication_endpoints_self_api_v1() to authenticated;

create or replace function public.bind_principal_communication_endpoint_source_self_api_v1(
  p_communication_endpoint_id uuid,p_connected_source_id uuid,p_binding_role text default 'send_receive',p_transport_metadata jsonb default '{}'::jsonb
) returns jsonb language sql set search_path=pg_catalog,atlas,public as $function$
  select atlas.bind_principal_communication_endpoint_source_self_api_v1(p_communication_endpoint_id,p_connected_source_id,p_binding_role,p_transport_metadata);
$function$;
revoke all on function public.bind_principal_communication_endpoint_source_self_api_v1(uuid,uuid,text,jsonb) from public,anon;
grant execute on function public.bind_principal_communication_endpoint_source_self_api_v1(uuid,uuid,text,jsonb) to authenticated;

create or replace function public.register_principal_connected_source_self_api_v1(
  p_provider_key text,p_provider_account_key text,p_display_label text default null,p_account_hint text default null,
  p_granted_scopes text[] default '{}'::text[],p_capabilities jsonb default '{}'::jsonb,p_metadata jsonb default '{}'::jsonb
) returns jsonb language sql set search_path=pg_catalog,atlas,public as $function$
  select atlas.register_principal_connected_source_self_api_v1(p_provider_key,p_provider_account_key,p_display_label,p_account_hint,p_granted_scopes,p_capabilities,p_metadata);
$function$;
revoke all on function public.register_principal_connected_source_self_api_v1(text,text,text,text,text[],jsonb,jsonb) from public,anon;
grant execute on function public.register_principal_connected_source_self_api_v1(text,text,text,text,text[],jsonb,jsonb) to authenticated;

create or replace function public.principal_communication_conversations_self_api_v1(
  p_communication_endpoint_id uuid default null,p_limit integer default 100
) returns table(
  communication_conversation_id uuid,subject text,conversation_state text,last_activity_at timestamptz,
  communication_endpoint_id uuid,endpoint_address text,last_communication_event_id uuid,last_event_direction text,last_event_at timestamptz,last_event_body text
) language sql stable set search_path=pg_catalog,atlas,public as $function$
  select * from atlas.principal_communication_conversations_self_api_v1(p_communication_endpoint_id,p_limit);
$function$;
revoke all on function public.principal_communication_conversations_self_api_v1(uuid,integer) from public,anon;
grant execute on function public.principal_communication_conversations_self_api_v1(uuid,integer) to authenticated;

create or replace function public.principal_communication_conversation_detail_self_api_v1(p_communication_conversation_id uuid)
returns jsonb language sql stable set search_path=pg_catalog,atlas,public as $function$
  select atlas.principal_communication_conversation_detail_self_api_v1(p_communication_conversation_id);
$function$;
revoke all on function public.principal_communication_conversation_detail_self_api_v1(uuid) from public,anon;
grant execute on function public.principal_communication_conversation_detail_self_api_v1(uuid) to authenticated;

create or replace function public.ingest_principal_communication_events_service_v1(p_connected_source_id uuid,p_events jsonb,p_manifest jsonb default '{}'::jsonb)
returns jsonb language sql set search_path=pg_catalog,atlas,public as $function$
  select atlas.ingest_principal_communication_events_service_v1(p_connected_source_id,p_events,p_manifest);
$function$;
revoke all on function public.ingest_principal_communication_events_service_v1(uuid,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.ingest_principal_communication_events_service_v1(uuid,jsonb,jsonb) to service_role;

-- Existing Vault custody is exposed to the application server only. Browser
-- roles remain unable to read or write provider credentials.
create or replace function public.store_connected_source_secret_service_v1(p_connected_source_id uuid,p_credential_kind text,p_secret text,p_description text default null)
returns jsonb language sql set search_path=pg_catalog,atlas,public as $function$
  select atlas.store_connected_source_secret_service_v1(p_connected_source_id,p_credential_kind,p_secret,p_description);
$function$;
revoke all on function public.store_connected_source_secret_service_v1(uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.store_connected_source_secret_service_v1(uuid,text,text,text) to service_role;

create or replace function public.read_connected_source_secret_service_v1(p_connected_source_id uuid,p_credential_kind text)
returns text language sql stable set search_path=pg_catalog,atlas,public as $function$
  select atlas.read_connected_source_secret_service_v1(p_connected_source_id,p_credential_kind);
$function$;
revoke all on function public.read_connected_source_secret_service_v1(uuid,text) from public,anon,authenticated;
grant execute on function public.read_connected_source_secret_service_v1(uuid,text) to service_role;

commit;