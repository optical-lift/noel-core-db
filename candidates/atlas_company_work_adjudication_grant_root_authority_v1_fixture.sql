-- Clone-only fixture for Atlas Company Work Adjudication Grant Root Authority v1.
-- Fixture is applied before the candidate migration. It creates a non-Principal
-- Organization owner, a root-governing Principal whose Organization role is only
-- member, a grant target member, and a historical owner-compatibility grant.

insert into auth.users(id,email,created_at,updated_at)
values
(
  'f4c00000-0000-4000-8000-000000000001'::uuid,
  'authority-root-principal@example.invalid',now(),now()
),
(
  'f4c00000-0000-4000-8000-000000000002'::uuid,
  'authority-root-owner@example.invalid',now(),now()
),
(
  'f4c00000-0000-4000-8000-000000000003'::uuid,
  'authority-root-target@example.invalid',now(),now()
);

insert into atlas.people(id,display_name,status,metadata)
values
(
  'f4c00000-0000-4000-8000-000000000011'::uuid,
  'Authority Root Principal','active','{"validationFixture":true}'::jsonb
),
(
  'f4c00000-0000-4000-8000-000000000012'::uuid,
  'Authority Root Owner','active','{"validationFixture":true}'::jsonb
),
(
  'f4c00000-0000-4000-8000-000000000013'::uuid,
  'Authority Root Target','active','{"validationFixture":true}'::jsonb
);

insert into atlas.person_auth_credentials(
  person_id,auth_user_id,credential_kind,status,provenance
)
values
(
  'f4c00000-0000-4000-8000-000000000011'::uuid,
  'f4c00000-0000-4000-8000-000000000001'::uuid,
  'supabase_auth_user','active','{"validationFixture":true}'::jsonb
),
(
  'f4c00000-0000-4000-8000-000000000012'::uuid,
  'f4c00000-0000-4000-8000-000000000002'::uuid,
  'supabase_auth_user','active','{"validationFixture":true}'::jsonb
),
(
  'f4c00000-0000-4000-8000-000000000013'::uuid,
  'f4c00000-0000-4000-8000-000000000003'::uuid,
  'supabase_auth_user','active','{"validationFixture":true}'::jsonb
);

insert into atlas.organizations(
  id,stable_key,name,status,metadata,onboarding_state
) values (
  'f4c00000-0000-4000-8000-000000000020'::uuid,
  'authority-root-proof-org',
  'Authority Root Proof Organization',
  'active','{"validationFixture":true}'::jsonb,'ready'
);

insert into atlas.ledgers(
  id,stable_key,organization_id,ledger_kind,status,metadata,name
) values (
  'f4c00000-0000-4000-8000-000000000021'::uuid,
  'authority-root-proof-ledger',
  'f4c00000-0000-4000-8000-000000000020'::uuid,
  'governed_reality','active',
  '{"validationFixture":true}'::jsonb,
  'Authority Root Proof Ledger'
);

insert into atlas.ledger_organization_participations(
  id,ledger_id,organization_id,participation_kind,is_compatibility_primary,
  status,basis,metadata
) values (
  'f4c00000-0000-4000-8000-000000000022'::uuid,
  'f4c00000-0000-4000-8000-000000000021'::uuid,
  'f4c00000-0000-4000-8000-000000000020'::uuid,
  'governing',true,'active',
  '{"kind":"validation_fixture","reason":"prove exact Company Work authority root"}'::jsonb,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.organization_memberships(
  id,organization_id,user_id,role,active,person_id
)
values
(
  'f4c00000-0000-4000-8000-000000000031'::uuid,
  'f4c00000-0000-4000-8000-000000000020'::uuid,
  'f4c00000-0000-4000-8000-000000000001'::uuid,
  'member',true,
  'f4c00000-0000-4000-8000-000000000011'::uuid
),
(
  'f4c00000-0000-4000-8000-000000000032'::uuid,
  'f4c00000-0000-4000-8000-000000000020'::uuid,
  'f4c00000-0000-4000-8000-000000000002'::uuid,
  'owner',true,
  'f4c00000-0000-4000-8000-000000000012'::uuid
),
(
  'f4c00000-0000-4000-8000-000000000033'::uuid,
  'f4c00000-0000-4000-8000-000000000020'::uuid,
  'f4c00000-0000-4000-8000-000000000003'::uuid,
  'member',true,
  'f4c00000-0000-4000-8000-000000000013'::uuid
);

insert into atlas.principals(
  id,user_id,organization_id,stable_key,name,status,metadata,person_id
) values (
  'f4c00000-0000-4000-8000-000000000041'::uuid,
  'f4c00000-0000-4000-8000-000000000001'::uuid,
  'f4c00000-0000-4000-8000-000000000020'::uuid,
  'authority-root-principal',
  'Authority Root Principal',
  'active',
  '{"validationFixture":true}'::jsonb,
  'f4c00000-0000-4000-8000-000000000011'::uuid
);

insert into atlas.principal_ledger_authorities(
  id,principal_id,ledger_id,authority_kind,status,basis,metadata
) values (
  'f4c00000-0000-4000-8000-000000000042'::uuid,
  'f4c00000-0000-4000-8000-000000000041'::uuid,
  'f4c00000-0000-4000-8000-000000000021'::uuid,
  'root_governing','active',
  'validation fixture exact root-governing authority',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.work_result_contract_policies(
  contract_key,source_domain,acceptance_mode,active,description,metadata
) values (
  'grant_root_authority_proof_v1',
  'organization','manager_acceptance',true,
  'Validation-only Company Work result contract for authority-root proof.',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.work_items(
  id,organization_id,title,work_state,result_contract_key,metadata
) values (
  'f4c00000-0000-4000-8000-000000000101'::uuid,
  'f4c00000-0000-4000-8000-000000000020'::uuid,
  'Authority root proof Work',
  'open','grant_root_authority_proof_v1',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.work_execution_results(
  id,organization_id,work_item_id,result_kind,result_contract_key,
  idempotency_key,payload,reported_at,metadata
) values (
  'f4c00000-0000-4000-8000-000000000111'::uuid,
  'f4c00000-0000-4000-8000-000000000020'::uuid,
  'f4c00000-0000-4000-8000-000000000101'::uuid,
  'completed','grant_root_authority_proof_v1',
  'authority-root-proof-result',
  '{"workerObservation":"fixture"}'::jsonb,
  '2026-09-22 18:20:00+00',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.company_work_adjudication_authority_grants(
  id,organization_id,membership_id,authority_kind,scope_kind,scope_id,
  grant_state,granted_by_membership_id,grant_basis_kind,metadata
) values (
  'f4c00000-0000-4000-8000-000000000121'::uuid,
  'f4c00000-0000-4000-8000-000000000020'::uuid,
  'f4c00000-0000-4000-8000-000000000032'::uuid,
  'result_acceptance','organization',
  'f4c00000-0000-4000-8000-000000000020'::uuid,
  'active',
  'f4c00000-0000-4000-8000-000000000032'::uuid,
  'organization_owner_compatibility_cutover',
  '{"validationFixture":true,"historicalCompatibility":true}'::jsonb
);
