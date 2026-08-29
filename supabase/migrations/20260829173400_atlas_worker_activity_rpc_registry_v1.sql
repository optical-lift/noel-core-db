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
  'atlas.record_worker_activity_log_v1(uuid, date, text, text, uuid, timestamp with time zone, timestamp with time zone, text)',
  'app_endpoint',
  'verified',
  'active',
  true,
  true,
  false,
  1,
  0,
  '{"source":"atlas_worker_activity_rpc_registry_v1","purpose":"worker self-reported lived-day evidence writer"}'::jsonb,
  now(),
  false
),
(
  'atlas.worker_activity_logs_for_day_v1(uuid, uuid, date)',
  'app_endpoint',
  'verified',
  'active',
  true,
  true,
  false,
  1,
  0,
  '{"source":"atlas_worker_activity_rpc_registry_v1","purpose":"worker or management lived-day evidence reader"}'::jsonb,
  now(),
  false
),
(
  'atlas.retract_worker_activity_log_v1(uuid)',
  'app_endpoint',
  'verified',
  'active',
  true,
  true,
  false,
  1,
  0,
  '{"source":"atlas_worker_activity_rpc_registry_v1","purpose":"worker self-report soft retraction"}'::jsonb,
  now(),
  false
)
on conflict (signature) do update set
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