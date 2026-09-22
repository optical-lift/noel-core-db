-- Clone-only fixture for Atlas Authority-Required Reconciliation — Company Work Proof v1.
-- Builds one unresolved manager-acceptance Result under a real Organization owner
-- plus one non-owner member. No Decision Requirement or queue rows are persisted.

insert into auth.users(id,email,created_at,updated_at)
values
(
  'f4a00000-0000-4000-8000-000000000001'::uuid,
  'decision-proof-owner@example.invalid',
  now(),now()
),
(
  'f4a00000-0000-4000-8000-000000000002'::uuid,
  'decision-proof-member@example.invalid',
  now(),now()
);

insert into atlas.organizations(
  id,stable_key,name,status,metadata,onboarding_state
) values (
  'f4a00000-0000-4000-8000-000000000010'::uuid,
  'authority_required_decision_proof_org',
  'Authority Required Decision Proof Organization',
  'active',
  '{"validationFixture":true}'::jsonb,
  'ready'
);

insert into atlas.ledgers(
  id,stable_key,organization_id,ledger_kind,status,metadata,name
) values (
  'f4a00000-0000-4000-8000-000000000020'::uuid,
  'authority_required_decision_proof_ledger',
  'f4a00000-0000-4000-8000-000000000010'::uuid,
  'organization_governing',
  'active',
  '{"validationFixture":true}'::jsonb,
  'Authority Required Decision Proof Ledger'
);

insert into atlas.ledger_organization_participations(
  id,ledger_id,organization_id,participation_kind,is_compatibility_primary,
  status,basis,metadata
) values (
  'f4a00000-0000-4000-8000-000000000021'::uuid,
  'f4a00000-0000-4000-8000-000000000020'::uuid,
  'f4a00000-0000-4000-8000-000000000010'::uuid,
  'governing',
  true,
  'active',
  '{"kind":"validation_fixture","reason":"exercise real Company Work completion consequence"}'::jsonb,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.organization_memberships(
  id,organization_id,user_id,role,active
) values
(
  'f4a00000-0000-4000-8000-000000000031'::uuid,
  'f4a00000-0000-4000-8000-000000000010'::uuid,
  'f4a00000-0000-4000-8000-000000000001'::uuid,
  'owner',
  true
),
(
  'f4a00000-0000-4000-8000-000000000032'::uuid,
  'f4a00000-0000-4000-8000-000000000010'::uuid,
  'f4a00000-0000-4000-8000-000000000002'::uuid,
  'member',
  true
);

insert into atlas.work_result_contract_policies(
  contract_key,source_domain,acceptance_mode,active,description,metadata
) values (
  'authority_required_reconciliation_manager_acceptance_v1',
  'organization',
  'manager_acceptance',
  true,
  'Validation-only manager acceptance contract for authority-required reconciliation proof.',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.work_items(
  id,organization_id,title,work_state,result_contract_key,completed_at,metadata
) values (
  'f4a00000-0000-4000-8000-000000000101'::uuid,
  'f4a00000-0000-4000-8000-000000000010'::uuid,
  'Decision Requirement proof Work',
  'open',
  'authority_required_reconciliation_manager_acceptance_v1',
  null,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.work_execution_results(
  id,organization_id,work_item_id,result_kind,result_contract_key,
  idempotency_key,payload,reported_at,metadata
) values (
  'f4a00000-0000-4000-8000-000000000111'::uuid,
  'f4a00000-0000-4000-8000-000000000010'::uuid,
  'f4a00000-0000-4000-8000-000000000101'::uuid,
  'completed',
  'authority_required_reconciliation_manager_acceptance_v1',
  'authority-required-decision-proof-result',
  '{"workerObservation":"fixture payload must not cross the Decision Requirement read membrane"}'::jsonb,
  '2026-09-22 16:30:00+00',
  '{"validationFixture":true}'::jsonb
);
