-- Clone-only fixture for Reality/Ledger external Entity bridge v1.

insert into auth.users(id)
values ('f5100000-0000-4000-8000-000000000001'::uuid);

insert into reality.entities(id,stable_key,entity_kind,display_name,identity_state,metadata)
values
(
  'f5100000-0000-4000-8000-000000000001'::uuid,
  'lex',
  'person',
  'Lex',
  'canonical',
  '{"validationFixture":true}'::jsonb
),
(
  'f5100000-0000-4000-8000-000000000002'::uuid,
  'elm-farm',
  'business',
  'Elm Farm',
  'canonical',
  '{"validationFixture":true}'::jsonb
);

insert into reality.auth_person_bindings(
  auth_user_id,person_entity_id,binding_state,binding_basis
)
values (
  'f5100000-0000-4000-8000-000000000001'::uuid,
  'f5100000-0000-4000-8000-000000000001'::uuid,
  'active',
  '{"validationFixture":true}'::jsonb
);

insert into ledger.onboarding_cases(
  id,subject_entity_id,requested_by_person_entity_id,practitioner_person_entity_id,
  desired_ledger_name,onboarding_state,onboarding_basis
)
values
(
  'f5100000-0000-4000-8000-000000000010'::uuid,
  'f5100000-0000-4000-8000-000000000002'::uuid,
  'f5100000-0000-4000-8000-000000000001'::uuid,
  'f5100000-0000-4000-8000-000000000001'::uuid,
  'Elm Farm Venue Ledger',
  'ready_to_activate',
  '{"validationFixture":true}'::jsonb
),
(
  'f5100000-0000-4000-8000-000000000013'::uuid,
  'f5100000-0000-4000-8000-000000000002'::uuid,
  'f5100000-0000-4000-8000-000000000001'::uuid,
  'f5100000-0000-4000-8000-000000000001'::uuid,
  'Elm Farm Flower Ledger',
  'ready_to_activate',
  '{"validationFixture":true}'::jsonb
);

insert into ledger.ledgers(
  id,subject_entity_id,onboarding_case_id,stable_key,name,ledger_state,metadata
)
values
(
  'f5100000-0000-4000-8000-000000000011'::uuid,
  'f5100000-0000-4000-8000-000000000002'::uuid,
  'f5100000-0000-4000-8000-000000000010'::uuid,
  'elm-farm:venue',
  'Elm Farm Venue Ledger',
  'active',
  '{"validationFixture":true}'::jsonb
),
(
  'f5100000-0000-4000-8000-000000000014'::uuid,
  'f5100000-0000-4000-8000-000000000002'::uuid,
  'f5100000-0000-4000-8000-000000000013'::uuid,
  'elm-farm:flower',
  'Elm Farm Flower Ledger',
  'active',
  '{"validationFixture":true}'::jsonb
);

insert into ledger.seats(
  id,ledger_id,person_entity_id,seat_state,seat_basis
)
values
(
  'f5100000-0000-4000-8000-000000000012'::uuid,
  'f5100000-0000-4000-8000-000000000011'::uuid,
  'f5100000-0000-4000-8000-000000000001'::uuid,
  'active',
  '{"validationFixture":true}'::jsonb
),
(
  'f5100000-0000-4000-8000-000000000015'::uuid,
  'f5100000-0000-4000-8000-000000000014'::uuid,
  'f5100000-0000-4000-8000-000000000001'::uuid,
  'active',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.organizations(id,stable_key,name,status,metadata,onboarding_state)
values (
  'f5100000-0000-4000-8000-000000000020'::uuid,
  'validation_external_bridge_context_org',
  'Validation External Bridge Context',
  'active',
  '{"validationFixture":true}'::jsonb,
  'ready'
);

insert into local_intel.local_contexts(
  id,stable_key,organization_id,name,status,metadata
)
values (
  'f5100000-0000-4000-8000-000000000021'::uuid,
  'validation_external_bridge_context',
  'f5100000-0000-4000-8000-000000000020'::uuid,
  'Validation External Bridge Context',
  'active',
  '{"validationFixture":true}'::jsonb
);

insert into local_intel.entities(
  id,stable_key,entity_type,name,status,verification_state,metadata,local_context_id
)
values (
  'f5100000-0000-4000-8000-000000000030'::uuid,
  'validation-springfield-firm',
  'business',
  'Validation Springfield Firm',
  'active',
  'official_source_current',
  '{"validationFixture":true}'::jsonb,
  'f5100000-0000-4000-8000-000000000021'::uuid
);

insert into local_intel.contact_points(
  id,entity_id,contact_type,contact_value,context,contact_scope,is_primary,
  visibility,verification_state,deliverability_state,marketing_status,
  metadata,normalized_value
)
values (
  'f5100000-0000-4000-8000-000000000031'::uuid,
  'f5100000-0000-4000-8000-000000000030'::uuid,
  'email',
  'hello@validation.example',
  'professional',
  'direct',
  true,
  'public',
  'official_source_current',
  'unknown',
  'eligible',
  '{"validationFixture":true}'::jsonb,
  'hello@validation.example'
);
