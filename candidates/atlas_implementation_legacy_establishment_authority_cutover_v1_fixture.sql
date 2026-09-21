-- Clone-only fixture for legacy establishment authority cutover.

insert into auth.users(id) values
  ('f4400000-0000-4000-8000-000000000001'::uuid);

insert into atlas.implementation_practitioners(
  human_user_id,status,authorization_basis,metadata
) values (
  'f4400000-0000-4000-8000-000000000001'::uuid,
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
  'f4400000-0000-4000-8000-000000000101'::uuid,
  'stripe',
  'cs_validation_legacy_authority_cutover',
  'validation_legacy_authority_cutover',
  'Legacy Authority Cutover Proof',
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
  'f4400000-0000-4000-8000-000000000111'::uuid,
  'f4400000-0000-4000-8000-000000000101'::uuid,
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
  'f4400000-0000-4000-8000-000000000121'::uuid,
  'f4400000-0000-4000-8000-000000000111'::uuid,
  'f4400000-0000-4000-8000-000000000001'::uuid,
  'practitioner',
  true,
  now(),
  '{"validationFixture":true}'::jsonb,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.implementation_establishment_items(
  id,
  implementation_case_id,
  category,
  title,
  detail,
  status,
  author_user_id,
  basis
) values (
  'f4400000-0000-4000-8000-000000000131'::uuid,
  'f4400000-0000-4000-8000-000000000111'::uuid,
  'institution',
  'Historical established coordination material',
  'Must remain historical rather than being rewritten.',
  'established',
  'f4400000-0000-4000-8000-000000000001'::uuid,
  '{"validationFixture":true,"historical":true}'::jsonb
);
