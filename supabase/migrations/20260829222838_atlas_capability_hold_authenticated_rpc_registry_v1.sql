insert into atlas.authenticated_rpc_registry (
  signature,
  classification,
  confidence,
  review_status,
  authenticated_execute_expected,
  security_definer_expected,
  service_execute_expected,
  caller_count,
  policy_reference_count,
  evidence,
  anonymous_execute_expected
) values
(
  'atlas.capability_hold_pool_v1(uuid)',
  'owner_admin_endpoint',
  'verified',
  'active',
  true,
  true,
  false,
  0,
  0,
  jsonb_build_object(
    'source','atlas_capability_hold_authenticated_rpc_registry_v1',
    'reason','Register the owner/manager capability-hold pool read endpoint introduced by atlas_capability_hold_pool_and_event_lifetime_v1.',
    'truthBoundary','Reads retained obligations waiting for capability; does not release, complete, or reschedule work.',
    'classificationRuleVersion',3
  ),
  false
),
(
  'atlas.owner_set_task_capability_hold_v1(uuid, text, text[], text, text)',
  'owner_admin_endpoint',
  'verified',
  'active',
  true,
  true,
  false,
  0,
  0,
  jsonb_build_object(
    'source','atlas_capability_hold_authenticated_rpc_registry_v1',
    'reason','Register the farm-owner capability-hold mutation endpoint introduced by atlas_capability_hold_pool_and_event_lifetime_v1.',
    'truthBoundary','Owner may hold or release execution eligibility without deleting the obligation or silently moving its original due truth.',
    'classificationRuleVersion',3
  ),
  false
)
on conflict (signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  anonymous_execute_expected=excluded.anonymous_execute_expected,
  reviewed_at=now();