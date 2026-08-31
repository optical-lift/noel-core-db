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
  'atlas.company_work_position_api_v1(uuid)',
  'owner_admin_endpoint',
  'verified',
  'active',
  true,
  true,
  true,
  0,
  0,
  jsonb_build_object(
    'source','atlas_company_work_position_rpc_registry_custody_v1',
    'reason','Register the owner-authorized Company Work position reader introduced by atlas_company_work_position_api_v1.',
    'authorization','Active organization owner membership is enforced inside the security-definer function.',
    'truthBoundary','Read-only projection of canonical organization Company Work; does not assign, complete, reschedule, or mutate work.',
    'classificationRuleVersion',3
  ),
  false
),
(
  'atlas.company_work_position_api_v2(uuid, uuid)',
  'owner_admin_endpoint',
  'verified',
  'active',
  true,
  true,
  true,
  0,
  0,
  jsonb_build_object(
    'source','atlas_company_work_position_rpc_registry_custody_v1',
    'reason','Register the owner-authorized Company Work position reader with optional Organization Unit scope introduced by atlas_organization_unit_custody_v1.',
    'authorization','Active organization owner membership is enforced inside the security-definer function; supplied Organization Unit scope must belong to that organization.',
    'truthBoundary','Read-only projection of canonical organization Company Work; NULL unit returns organization-wide position and no work authority is mutated.',
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
