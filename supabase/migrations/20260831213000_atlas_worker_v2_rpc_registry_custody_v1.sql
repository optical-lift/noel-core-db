-- Atlas Worker Day v2 RPC Registry Custody v1
--
-- 20260831204000 deliberately retired worker_day_operational_task_cards_v2
-- as a direct authenticated presentation surface and kept it only as a
-- service-role compatibility builder. Align the authenticated RPC registry
-- with that already-live privilege contract; do not re-grant authenticated use.

begin;

update atlas.authenticated_rpc_registry
set
  classification = 'service_internal',
  review_status = 'revoked',
  authenticated_execute_expected = false,
  security_definer_expected = true,
  service_execute_expected = true,
  caller_count = 0,
  evidence = coalesce(evidence, '{}'::jsonb) || jsonb_build_object(
    'source','atlas_worker_v2_rpc_registry_custody_v1',
    'purpose','Keep worker_day_operational_task_cards_v2 as a service-only compatibility builder after Worker Day presentation moved to v3.',
    'boundary','Migration 20260831204000 explicitly revoked public, anon, and authenticated execution and retained service_role execution only. This migration reconciles registry custody to that canonical live behavior; it does not change function implementation or privileges.',
    'truthBoundary','worker_day_operational_task_cards_v2 is not a direct authenticated Worker Day presentation endpoint. Worker-facing bundles use worker_day_operational_task_cards_v3.',
    'classificationRuleVersion',3
  ),
  reviewed_at = now()
where signature = 'atlas.worker_day_operational_task_cards_v2(uuid, uuid, date, uuid[])';

do $invariants$
begin
  if not exists (
    select 1
    from atlas.authenticated_rpc_registry registry
    where registry.signature = 'atlas.worker_day_operational_task_cards_v2(uuid, uuid, date, uuid[])'
      and registry.classification = 'service_internal'
      and registry.review_status = 'revoked'
      and registry.authenticated_execute_expected = false
      and registry.service_execute_expected = true
  ) then
    raise exception 'Worker Day v2 RPC registry custody row did not reconcile.';
  end if;

  if exists (
    select 1
    from atlas.authenticated_rpc_registry_drift_v1() drift
    where drift.signature = 'atlas.worker_day_operational_task_cards_v2(uuid, uuid, date, uuid[])'
  ) then
    raise exception 'Worker Day v2 RPC registry drift remains.';
  end if;
end;
$invariants$;

commit;
