insert into atlas.authenticated_rpc_registry (signature, classification, confidence, review_status, authenticated_execute_expected, security_definer_expected, service_execute_expected, caller_count, policy_reference_count, evidence, reviewed_at, anonymous_execute_expected)
values
('atlas.current_organization_membership_v1(uuid)', 'policy_or_composition_helper', 'verified', 'active', true, true, true, 1, 0, '{"source":"atlas_operational_route_rpc_registry_custody_v1","purpose":"organization membership resolver"}'::jsonb, now(), false),
('atlas.require_operational_route_owner_v1(uuid)', 'owner_admin_endpoint', 'verified', 'active', true, true, true, 1, 0, '{"source":"atlas_operational_route_rpc_registry_custody_v1","purpose":"organization route authority guard"}'::jsonb, now(), false)
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
reviewed_at=excluded.reviewed_at,
anonymous_execute_expected=excluded.anonymous_execute_expected;