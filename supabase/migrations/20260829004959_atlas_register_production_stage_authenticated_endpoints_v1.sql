insert into atlas.authenticated_rpc_registry(
  signature, classification, confidence, review_status,
  authenticated_execute_expected, security_definer_expected, service_execute_expected,
  caller_count, policy_reference_count, evidence, reviewed_at, anonymous_execute_expected
)
values
  (
    'atlas.worker_record_production_hardening_v1(uuid, date, text, text)',
    'app_endpoint','verified','active',true,true,false,0,0,
    jsonb_build_object(
      'source','atlas_register_production_stage_authenticated_endpoints_v1',
      'reason','register production hardening worker endpoint created by production_stage_authorization_wrappers_v1',
      'truthBoundary','Assigned worker may record the governed hardening stage result; the wrapper validates task assignment and current execution readiness before calling the internal production-stage recorder.',
      'classificationRuleVersion',3
    ), now(), false
  ),
  (
    'atlas.owner_record_production_hardening_v1(uuid, date, text, text)',
    'owner_admin_endpoint','verified','active',true,true,false,0,0,
    jsonb_build_object(
      'source','atlas_register_production_stage_authenticated_endpoints_v1',
      'reason','register production hardening owner endpoint created by production_stage_authorization_wrappers_v1',
      'truthBoundary','Farm Owner may record the governed hardening stage result for a task in the owned farm; the domain recorder remains authoritative for production state.',
      'classificationRuleVersion',3
    ), now(), false
  ),
  (
    'atlas.owner_operator_record_production_hardening_v1(uuid, uuid, date, text, text)',
    'owner_admin_endpoint','verified','active',true,true,false,0,0,
    jsonb_build_object(
      'source','atlas_register_production_stage_authenticated_endpoints_v1',
      'reason','register production hardening owner-operator endpoint created by production_stage_authorization_wrappers_v1',
      'truthBoundary','Owner operator mode may record hardening only inside the selected effective farm-member context after visibility validation.',
      'classificationRuleVersion',3
    ), now(), false
  ),
  (
    'atlas.worker_record_production_readiness_v1(uuid, text, numeric, numeric, date, date, text, text)',
    'app_endpoint','verified','active',true,true,false,0,0,
    jsonb_build_object(
      'source','atlas_register_production_stage_authenticated_endpoints_v1',
      'reason','register production readiness worker endpoint created by production_stage_authorization_wrappers_v1',
      'truthBoundary','Assigned worker may record governed transplant-readiness observations; ready and failed outcomes require current execution readiness and the production readiness recorder owns biological state.',
      'classificationRuleVersion',3
    ), now(), false
  ),
  (
    'atlas.owner_record_production_readiness_v1(uuid, text, numeric, numeric, date, date, text, text)',
    'owner_admin_endpoint','verified','active',true,true,false,0,0,
    jsonb_build_object(
      'source','atlas_register_production_stage_authenticated_endpoints_v1',
      'reason','register production readiness owner endpoint created by production_stage_authorization_wrappers_v1',
      'truthBoundary','Farm Owner may record governed production-readiness observations for a task in the owned farm; the domain recorder owns biological state and continuation.',
      'classificationRuleVersion',3
    ), now(), false
  ),
  (
    'atlas.owner_operator_record_production_readiness_v1(uuid, uuid, text, numeric, numeric, date, date, text, text)',
    'owner_admin_endpoint','verified','active',true,true,false,0,0,
    jsonb_build_object(
      'source','atlas_register_production_stage_authenticated_endpoints_v1',
      'reason','register production readiness owner-operator endpoint created by production_stage_authorization_wrappers_v1',
      'truthBoundary','Owner operator mode may record production readiness only inside the selected effective farm-member context after visibility validation.',
      'classificationRuleVersion',3
    ), now(), false
  )
on conflict(signature) do update set
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