-- Clone-only fixture for Personal Institutional Anchor Resolver v1.
-- Requires Personal Reality Institutional Anchor v1 to be live in the clone.

insert into auth.users(id,email,created_at,updated_at)
values (
  'f6b10000-0000-4000-8000-000000000001'::uuid,
  'institutional-resolver-proof@example.invalid',
  now(),now()
);

insert into atlas.principals(
  id,user_id,stable_key,name,home_timezone,status,metadata
) values (
  'f6b10000-0000-4000-8000-000000000002'::uuid,
  'f6b10000-0000-4000-8000-000000000001'::uuid,
  'validation:personal-institutional-resolver-v1',
  'Institutional Resolver Proof',
  'America/Chicago',
  'active',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.evidence_records(
  id,scope_kind,scope_id,subject_domain,subject_kind,subject_id,
  evidence_kind,source_kind,source_key,actor_user_id,value,confidence,
  provenance,metadata
) values (
  'f6b10000-0000-4000-8000-000000000003'::uuid,
  'person',
  'f6b10000-0000-4000-8000-000000000001'::uuid,
  'personal.reality',
  'testimony',
  'f6b10000-0000-4000-8000-000000000004',
  'first_party_testimony',
  'personal_reality_capture',
  'validation:personal-institutional-resolver-v1',
  'f6b10000-0000-4000-8000-000000000001'::uuid,
  '{"testimony":"Payroll is Friday."}'::jsonb,
  1,
  '{"source":"validation_fixture"}'::jsonb,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.personal_reality_captures(
  id,principal_id,owner_user_id,source_action_id,testimony,evidence_id,
  capture_state,source_surface,capture_context,metadata
) values (
  'f6b10000-0000-4000-8000-000000000004'::uuid,
  'f6b10000-0000-4000-8000-000000000002'::uuid,
  'f6b10000-0000-4000-8000-000000000001'::uuid,
  'validation:personal-institutional-resolver-v1',
  'Payroll is Friday.',
  'f6b10000-0000-4000-8000-000000000003'::uuid,
  'captured',
  'tell_atlas',
  '{"notebookAddress":"today","encounterKind":"tell_atlas"}'::jsonb,
  '{"validationFixture":true}'::jsonb
);
