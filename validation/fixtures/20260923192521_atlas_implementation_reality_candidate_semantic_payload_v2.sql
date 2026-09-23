-- Clone-only fixture for Atlas Implementation Reality Candidate Semantic Payload v2.
-- Establishes one practitioner and one open Implementation Case. The candidate
-- migration itself adds only additive custody/membranes.

insert into auth.users(id) values
  ('f4600000-0000-4000-8000-000000000001'::uuid);

insert into atlas.implementation_practitioners(
  human_user_id,status,authorization_basis,metadata
) values (
  'f4600000-0000-4000-8000-000000000001'::uuid,
  'active',
  '{"validationFixture":true}'::jsonb,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.implementation_purchases(
  id,
  provider,
  provider_checkout_session_id,
  offer_key,
  starting_label,
  payment_option,
  purchase_state,
  currency,
  setup_contract_amount_cents,
  monthly_ledger_unit_price_cents,
  metadata
) values (
  'f4600000-0000-4000-8000-000000000101'::uuid,
  'stripe',
  'cs_validation_reality_semantic_payload_v2',
  'validation_reality_semantic_payload_v2',
  'Semantic Payload Validation Organization',
  'pay_in_full',
  'active',
  'usd',
  0,
  0,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.implementation_cases(
  id,implementation_purchase_id,state,metadata
) values (
  'f4600000-0000-4000-8000-000000000111'::uuid,
  'f4600000-0000-4000-8000-000000000101'::uuid,
  'in_implementation',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.implementation_case_participants(
  id,
  implementation_case_id,
  human_user_id,
  relationship_kind,
  active,
  verified_at,
  basis,
  metadata
) values (
  'f4600000-0000-4000-8000-000000000121'::uuid,
  'f4600000-0000-4000-8000-000000000111'::uuid,
  'f4600000-0000-4000-8000-000000000001'::uuid,
  'practitioner',
  true,
  now(),
  '{"validationFixture":true}'::jsonb,
  '{"validationFixture":true}'::jsonb
);
