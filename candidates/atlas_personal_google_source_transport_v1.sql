-- Source candidate only. DO NOT APPLY TO PRODUCTION DIRECTLY.
-- First release requires the current-canon provider session migration
-- 20260919233031 to exist. These narrow service-role-only wrappers let the
-- existing Atlas server RPC transport call canonical atlas functions over the
-- intentionally exposed public profile. No new Connected Source writer.
--
-- Service-only is deliberate: ordinary authenticated/anon roles may not
-- complete identity, activate provider scope or store reusable secrets.
create or replace function public.complete_provider_connection_identity_service_v1(
  p_session_id uuid,
  p_provider_account_key text,
  p_display_label text default null,
  p_account_hint text default null,
  p_granted_scopes text[] default '{}'::text[],
  p_capabilities jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
) returns jsonb
language sql security definer
set search_path=pg_catalog,atlas
as $fn$
  select atlas.complete_provider_connection_identity_service_v1(
    p_session_id,p_provider_account_key,p_display_label,p_account_hint,
    p_granted_scopes,p_capabilities,p_metadata
  )
$fn$;
revoke all on function public.complete_provider_connection_identity_service_v1(
  uuid,text,text,text,text[],jsonb,jsonb
) from public,anon,authenticated;
grant execute on function public.complete_provider_connection_identity_service_v1(
  uuid,text,text,text,text[],jsonb,jsonb
) to service_role;

create or replace function public.activate_provider_connection_service_v1(
  p_session_id uuid,
  p_required_credential_kind text,
  p_metadata jsonb default '{}'::jsonb
) returns jsonb
language sql security definer
set search_path=pg_catalog,atlas
as $fn$
  select atlas.activate_provider_connection_service_v1(
    p_session_id,p_required_credential_kind,p_metadata
  )
$fn$;
revoke all on function public.activate_provider_connection_service_v1(
  uuid,text,jsonb
) from public,anon,authenticated;
grant execute on function public.activate_provider_connection_service_v1(
  uuid,text,jsonb
) to service_role;

create or replace function public.store_connected_source_secret_service_v1(
  p_connected_source_id uuid,
  p_credential_kind text,
  p_secret text,
  p_description text default null
) returns jsonb
language sql security definer
set search_path=pg_catalog,atlas
as $fn$
  select atlas.store_connected_source_secret_service_v1(
    p_connected_source_id,p_credential_kind,p_secret,p_description
  )
$fn$;
revoke all on function public.store_connected_source_secret_service_v1(
  uuid,text,text,text
) from public,anon,authenticated;
grant execute on function public.store_connected_source_secret_service_v1(
  uuid,text,text,text
) to service_role;
