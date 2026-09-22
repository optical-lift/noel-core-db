insert into auth.users(id,email,created_at,updated_at)
values ('f6d10000-0000-4000-8000-000000000001'::uuid,'institutional-handoff-proof@example.invalid',now(),now());

insert into atlas.principals(id,user_id,stable_key,name,home_timezone,status,metadata)
values ('f6d10000-0000-4000-8000-000000000002'::uuid,'f6d10000-0000-4000-8000-000000000001'::uuid,
'validation:personal-institutional-handoff-v1','Institutional Handoff Proof','America/Chicago','active','{"validationFixture":true}'::jsonb);

insert into atlas.evidence_records(
  id,scope_kind,scope_id,subject_domain,subject_kind,subject_id,
  evidence_kind,source_kind,source_key,actor_user_id,value,confidence,provenance,metadata
) values (
  'f6d10000-0000-4000-8000-000000000003'::uuid,'person','f6d10000-0000-4000-8000-000000000001'::uuid,
  'personal.reality','testimony','f6d10000-0000-4000-8000-000000000004','first_party_testimony',
  'personal_reality_capture','validation:personal-institutional-handoff-v1','f6d10000-0000-4000-8000-000000000001'::uuid,
  '{"testimony":"Payroll is Friday."}'::jsonb,1,'{"source":"validation_fixture"}'::jsonb,'{"validationFixture":true}'::jsonb
);

insert into atlas.personal_reality_captures(
  id,principal_id,owner_user_id,source_action_id,testimony,evidence_id,capture_state,source_surface,capture_context,metadata
) values (
  'f6d10000-0000-4000-8000-000000000004'::uuid,'f6d10000-0000-4000-8000-000000000002'::uuid,
  'f6d10000-0000-4000-8000-000000000001'::uuid,'validation:personal-institutional-handoff-v1','Payroll is Friday.',
  'f6d10000-0000-4000-8000-000000000003'::uuid,'captured','tell_atlas',
  '{"notebookAddress":"today","encounterKind":"tell_atlas"}'::jsonb,'{"validationFixture":true}'::jsonb
);

insert into atlas.implementation_purchases(
  id,provider_checkout_session_id,offer_key,starting_label,payment_option,
  setup_contract_amount_cents,monthly_ledger_unit_price_cents,metadata
) values (
  'f6d10000-0000-4000-8000-000000000010'::uuid,'validation_checkout_personal_institutional_handoff_v1',
  'validation_implementation','Fixture Implementation','pay_in_full',300000,40000,'{"validationFixture":true}'::jsonb
);

insert into atlas.implementation_cases(id,implementation_purchase_id,state,metadata)
values ('f6d10000-0000-4000-8000-000000000011'::uuid,'f6d10000-0000-4000-8000-000000000010'::uuid,
'in_implementation','{"validationFixture":true}'::jsonb);

insert into atlas.implementation_case_participants(
  id,implementation_case_id,human_user_id,relationship_kind,active,verified_at,basis,metadata
) values (
  'f6d10000-0000-4000-8000-000000000012'::uuid,'f6d10000-0000-4000-8000-000000000011'::uuid,
  'f6d10000-0000-4000-8000-000000000001'::uuid,'setup_sponsor',true,now(),
  '{"kind":"validation_fixture"}'::jsonb,'{"validationFixture":true}'::jsonb
);
