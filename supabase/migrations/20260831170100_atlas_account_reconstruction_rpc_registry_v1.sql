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
) values (
  'atlas.connected_sources_self_api_v1()',
  'app_endpoint',
  'verified',
  'active',
  true,
  true,
  true,
  0,
  0,
  jsonb_build_object(
    'source','atlas_account_reconstruction_rpc_registry_v1',
    'purpose','Return the current human connected-source registry plus sources held by organizations in which that human has active membership.',
    'boundary','No caller-supplied human identity; auth.uid scopes human custody and active organization membership scopes institutional custody. No reusable provider credentials are stored or returned.',
    'truthBoundary','Read-only source-registry projection; does not authorize a provider, create a reconstruction session, admit evidence, or mutate Atlas canon.',
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
