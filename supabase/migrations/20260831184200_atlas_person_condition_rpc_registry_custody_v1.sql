-- Register the authenticated person-owned condition observation endpoint in
-- Atlas RPC custody after its first-party write membrane became live.

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
values (
  'atlas.record_person_condition_observation_api_v1(jsonb)',
  'app_endpoint',
  'verified',
  'active',
  true,
  true,
  true,
  0,
  0,
  jsonb_build_object(
    'purpose', 'Record a provenance-backed person-owned condition observation without diagnosing, scheduling, or granting practitioner access.',
    'authorizationBoundary', 'The SECURITY DEFINER function requires auth.uid() and stores the observation under that person scope.',
    'directSignedInEndpoint', true
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

do $$
begin
  if exists (select 1 from atlas.authenticated_rpc_registry_drift_v1()) then
    raise exception 'Authenticated RPC registry remains incomplete after person-condition custody registration.';
  end if;
end
$$;

commit;
