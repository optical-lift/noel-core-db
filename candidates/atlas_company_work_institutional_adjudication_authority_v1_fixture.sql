-- Clone-only fixture for Atlas Company Work Institutional Adjudication Authority v1.
-- Creates an owner, an explicit future adjudicator, and an unrelated member.
-- None receives adjudication authority from role/title/responsibility alone.

insert into auth.users(id,email,created_at,updated_at)
values
(
  'f4b00000-0000-4000-8000-000000000001'::uuid,
  'adjudication-proof-owner@example.invalid',now(),now()
),
(
  'f4b00000-0000-4000-8000-000000000002'::uuid,
  'adjudication-proof-grantee@example.invalid',now(),now()
),
(
  'f4b00000-0000-4000-8000-000000000003'::uuid,
  'adjudication-proof-other@example.invalid',now(),now()
);

insert into atlas.people(id,display_name,status,metadata)
values
(
  'f4b00000-0000-4000-8000-000000000011'::uuid,
  'Adjudication Proof Owner','active',
  '{"validationFixture":true}'::jsonb
),
(
  'f4b00000-0000-4000-8000-000000000012'::uuid,
  'Adjudication Proof Grantee','active',
  '{"validationFixture":true}'::jsonb
),
(
  'f4b00000-0000-4000-8000-000000000013'::uuid,
  'Adjudication Proof Other','active',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.person_auth_credentials(
  person_id,auth_user_id,credential_kind,status,provenance
)
values
(
  'f4b00000-0000-4000-8000-000000000011'::uuid,
  'f4b00000-0000-4000-8000-000000000001'::uuid,
  'supabase_auth_user','active','{"validationFixture":true}'::jsonb
),
(
  'f4b00000-0000-4000-8000-000000000012'::uuid,
  'f4b00000-0000-4000-8000-000000000002'::uuid,
  'supabase_auth_user','active','{"validationFixture":true}'::jsonb
),
(
  'f4b00000-0000-4000-8000-000000000013'::uuid,
  'f4b00000-0000-4000-8000-000000000003'::uuid,
  'supabase_auth_user','active','{"validationFixture":true}'::jsonb
);

insert into atlas.organizations(
  id,stable_key,name,status,metadata,onboarding_state
) values (
  'f4b00000-0000-4000-8000-000000000020'::uuid,
  'adjudication-authority-proof-org',
  'Adjudication Authority Proof Organization',
  'active','{"validationFixture":true}'::jsonb,'ready'
);

insert into atlas.ledgers(
  id,stable_key,organization_id,ledger_kind,status,metadata,name
) values (
  'f4b00000-0000-4000-8000-000000000021'::uuid,
  'adjudication-authority-proof-ledger',
  'f4b00000-0000-4000-8000-000000000020'::uuid,
  'organization_governing','active',
  '{"validationFixture":true}'::jsonb,
  'Adjudication Authority Proof Ledger'
);

insert into atlas.ledger_organization_participations(
  id,ledger_id,organization_id,participation_kind,is_compatibility_primary,
  status,basis,metadata
) values (
  'f4b00000-0000-4000-8000-000000000022'::uuid,
  'f4b00000-0000-4000-8000-000000000021'::uuid,
  'f4b00000-0000-4000-8000-000000000020'::uuid,
  'governing',true,'active',
  '{"kind":"validation_fixture","reason":"exercise real Company Work consequence projection"}'::jsonb,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.organization_memberships(
  id,organization_id,user_id,role,active,person_id
)
values
(
  'f4b00000-0000-4000-8000-000000000031'::uuid,
  'f4b00000-0000-4000-8000-000000000020'::uuid,
  'f4b00000-0000-4000-8000-000000000001'::uuid,
  'owner',true,
  'f4b00000-0000-4000-8000-000000000011'::uuid
),
(
  'f4b00000-0000-4000-8000-000000000032'::uuid,
  'f4b00000-0000-4000-8000-000000000020'::uuid,
  'f4b00000-0000-4000-8000-000000000002'::uuid,
  'member',true,
  'f4b00000-0000-4000-8000-000000000012'::uuid
),
(
  'f4b00000-0000-4000-8000-000000000033'::uuid,
  'f4b00000-0000-4000-8000-000000000020'::uuid,
  'f4b00000-0000-4000-8000-000000000003'::uuid,
  'member',true,
  'f4b00000-0000-4000-8000-000000000013'::uuid
);

insert into atlas.work_result_contract_policies(
  contract_key,source_domain,acceptance_mode,active,description,metadata
) values (
  'institutional_adjudication_authority_proof_v1',
  'organization','manager_acceptance',true,
  'Validation-only manager acceptance contract for explicit adjudication authority proof.',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.work_items(
  id,organization_id,title,work_state,result_contract_key,metadata
)
values
(
  'f4b00000-0000-4000-8000-000000000101'::uuid,
  'f4b00000-0000-4000-8000-000000000020'::uuid,
  'Exact-scope adjudication proof Work',
  'open','institutional_adjudication_authority_proof_v1',
  '{"validationFixture":true}'::jsonb
),
(
  'f4b00000-0000-4000-8000-000000000102'::uuid,
  'f4b00000-0000-4000-8000-000000000020'::uuid,
  'Sibling adjudication proof Work',
  'open','institutional_adjudication_authority_proof_v1',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.work_execution_results(
  id,organization_id,work_item_id,result_kind,result_contract_key,
  idempotency_key,payload,reported_at,metadata
)
values
(
  'f4b00000-0000-4000-8000-000000000111'::uuid,
  'f4b00000-0000-4000-8000-000000000020'::uuid,
  'f4b00000-0000-4000-8000-000000000101'::uuid,
  'completed','institutional_adjudication_authority_proof_v1',
  'institutional-adjudication-authority-proof-a',
  '{"workerObservation":"must remain outside minimal Decision Requirement"}'::jsonb,
  '2026-09-22 17:10:00+00',
  '{"validationFixture":true}'::jsonb
),
(
  'f4b00000-0000-4000-8000-000000000112'::uuid,
  'f4b00000-0000-4000-8000-000000000020'::uuid,
  'f4b00000-0000-4000-8000-000000000102'::uuid,
  'completed','institutional_adjudication_authority_proof_v1',
  'institutional-adjudication-authority-proof-b',
  '{"workerObservation":"sibling result"}'::jsonb,
  '2026-09-22 17:11:00+00',
  '{"validationFixture":true}'::jsonb
);
