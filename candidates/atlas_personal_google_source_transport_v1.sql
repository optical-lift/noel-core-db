begin;

-- Source candidate only. DO NOT APPLY TO PRODUCTION DIRECTLY.
-- First release requires the current-canon provider session migration
-- 20260919233031 to exist. These narrow service-role-only wrappers let the
-- existing Atlas server RPC transport call canonical atlas functions over the
-- intentionally exposed public profile. No new Connected Source writer.
--
-- Service-only is deliberate: ordinary authenticated/anon roles may not
-- complete identity or activate provider scope.
create or replace function public.complete_provider_connection_identity_service_v1(
  p_session_id uuid,
  p_provider_account_key text,
  p_display_label text default null,
  p_account_hint text default null,
  p_granted_scopes text[] default '{}'::text[],
  p_capabilities jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
) returns jsonb
language sql security invoker
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
language sql security invoker
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


-- Vault secret store/read and Principal Communication ingestion already
-- have public service-role-only wrappers in 20260911174700.
-- Reusing them avoids duplicate authority and migration drift.

commit;
