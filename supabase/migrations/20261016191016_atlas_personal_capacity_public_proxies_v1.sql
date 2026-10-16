-- Source-only Atlas candidate; no production DDL until governed generated release.
-- Public authenticated RPC membranes for existing native Person-owned capacity.
-- No new data model, inferred schedules, or ownership grants.
begin;

create or replace function public.personal_capacity_policies_self_api_v1()
returns jsonb
language sql stable security definer
set search_path to ''
as $capacity_read$
  select atlas.personal_capacity_policies_self_api_v1();
$capacity_read$;
revoke all on function public.personal_capacity_policies_self_api_v1()
  from public,anon,authenticated;
grant execute on function public.personal_capacity_policies_self_api_v1()
  to authenticated;

create or replace function public.personal_set_capacity_policy_self_api_v1(p_input jsonb)
returns jsonb
language sql security definer
set search_path to ''
as $capacity_write$
  select atlas.personal_set_capacity_policy_self_api_v1(p_input);
$capacity_write$;
revoke all on function public.personal_set_capacity_policy_self_api_v1(jsonb)
  from public,anon,authenticated;
grant execute on function public.personal_set_capacity_policy_self_api_v1(jsonb)
  to authenticated;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,anonymous_execute_expected
) values
(
  'public.personal_capacity_policies_self_api_v1()',
  'app_endpoint','provisional','active',
  true,true,false,0,0,
  '{"source":"atlas_personal_capacity_public_proxies_v1","nativePersonAuthority":true,"readOnly":true}'::jsonb,false
),(
  'public.personal_set_capacity_policy_self_api_v1(jsonb)',
  'app_endpoint','provisional','active',
  true,true,false,0,0,
  '{"source":"atlas_personal_capacity_public_proxies_v1","nativePersonAuthority":true,"ownerConfirmedWrite":true}'::jsonb,false
)
on conflict(signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  evidence=atlas.authenticated_rpc_registry.evidence||excluded.evidence,
  anonymous_execute_expected=excluded.anonymous_execute_expected,
  reviewed_at=now();

commit;
