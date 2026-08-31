-- Register the authenticated Weekly Harvest v3/v2 membrane endpoints in the
-- canonical Atlas RPC custody registry. The functions already exist in the
-- preceding harvest migrations; this migration closes their registry drift only.

begin;

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
  reviewed_at,
  anonymous_execute_expected
)
values
  (
    'atlas.owner_operator_record_weekly_harvest_row_v3(uuid, uuid, uuid, text, text, integer, text)',
    'owner_admin_endpoint',
    'verified',
    'active',
    true,
    true,
    true,
    1,
    0,
    jsonb_build_object(
      'caller', 'POST /api/atlas/weekly-harvest',
      'purpose', 'Record one crop/bed weekly Harvest v3 result in Owner operator mode.',
      'authorizationBoundary', 'Owner operator context resolves the effective membership before the writer.'
    ),
    now(),
    false
  ),
  (
    'atlas.owner_operator_weekly_harvest_task_state_v2(uuid, uuid)',
    'owner_admin_endpoint',
    'verified',
    'active',
    true,
    true,
    true,
    1,
    0,
    jsonb_build_object(
      'caller', 'GET /api/atlas/weekly-harvest',
      'purpose', 'Read the current weekly Harvest v2 task state in Owner operator mode.',
      'authorizationBoundary', 'Owner operator context resolves the effective membership before reading task state.'
    ),
    now(),
    false
  ),
  (
    'atlas.record_weekly_harvest_row_for_member_v3(uuid, uuid, uuid, text, text, integer, text)',
    'app_endpoint',
    'verified',
    'active',
    true,
    true,
    true,
    1,
    0,
    jsonb_build_object(
      'caller', 'POST /api/atlas/weekly-harvest',
      'purpose', 'Record one crop/bed weekly Harvest v3 result for a signed-in farm member.',
      'authorizationBoundary', 'Wrapper resolves current farm membership before the writer.'
    ),
    now(),
    false
  ),
  (
    'atlas.weekly_harvest_task_state_for_member_v2(uuid, uuid)',
    'app_endpoint',
    'verified',
    'active',
    true,
    true,
    true,
    1,
    0,
    jsonb_build_object(
      'caller', 'GET /api/atlas/weekly-harvest',
      'purpose', 'Read the current weekly Harvest v2 task state for a signed-in farm member.',
      'authorizationBoundary', 'Wrapper resolves current farm role and membership before reading task state.'
    ),
    now(),
    false
  )
on conflict (signature) do update
set
  classification = excluded.classification,
  confidence = excluded.confidence,
  review_status = excluded.review_status,
  authenticated_execute_expected = excluded.authenticated_execute_expected,
  security_definer_expected = excluded.security_definer_expected,
  service_execute_expected = excluded.service_execute_expected,
  caller_count = excluded.caller_count,
  policy_reference_count = excluded.policy_reference_count,
  evidence = excluded.evidence,
  reviewed_at = excluded.reviewed_at,
  anonymous_execute_expected = excluded.anonymous_execute_expected;

select atlas.assert_authenticated_rpc_registry_complete_v1();

commit;
