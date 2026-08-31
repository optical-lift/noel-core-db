-- Atlas Communication RPC Registry Custody v1
--
-- Reconciles the two authenticated endpoints introduced by
-- 20260831193803_atlas_communication_ledger_v1 with the canonical
-- authenticated RPC registry. This changes no communication behavior.

begin;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,reviewed_at,anonymous_execute_expected
)
values
(
  'atlas.register_communication_relay_api_v1(text, text, text, text)',
  'app_endpoint','verified','active',true,true,true,0,0,
  jsonb_build_object(
    'source','atlas_communication_rpc_registry_custody_v1',
    'purpose','Pair a signed-in Principal with one communication relay source and rotate the source-specific relay credential.',
    'boundary','SECURITY DEFINER requires auth.uid(), resolves the active Principal from that identity, and creates or reconnects only a connected source whose custodian is that same user. The returned receipt does not admit communication evidence or change governing Atlas state.',
    'truthBoundary','Pairing establishes source custody and relay authorization only; communication content remains evidence-only until separately ingested.',
    'classificationRuleVersion',3,
    'directSignedInEndpoint',true
  ),now(),false
),
(
  'atlas.communication_source_health_self_api_v1()',
  'app_endpoint','verified','active',true,true,true,0,0,
  jsonb_build_object(
    'source','atlas_communication_rpc_registry_custody_v1',
    'purpose','Read communication-source freshness, event custody counts, and conflict counts for the signed-in human own connected sources.',
    'boundary','SECURITY DEFINER fixes the projection to auth.uid() and only communication-capable sources held by that custodian. It performs no writes.',
    'truthBoundary','Read-only source-health projection; does not infer communication meaning, authorize state change, or alter source custody.',
    'classificationRuleVersion',3,
    'directSignedInEndpoint',true
  ),now(),false
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
  reviewed_at=excluded.reviewed_at,
  anonymous_execute_expected=excluded.anonymous_execute_expected;

do $$
begin
  if exists (select 1 from atlas.authenticated_rpc_registry_drift_v1()) then
    raise exception 'Authenticated RPC registry remains incomplete after communication RPC custody reconciliation.';
  end if;
end
$$;

commit;
