-- Clone-only pre-migration fixture for Atlas Implementation Reality Candidate Custody v1.
-- The fixture creates only existing Implementation substrate. The candidate
-- migration itself creates the new Reality Candidate custody table.

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
) values
(
  'f4100000-0000-4000-8000-000000000101'::uuid,
  'stripe',
  'cs_validation_reality_candidate_1',
  'validation_reality_candidate',
  'Validation Reality Candidate One',
  'pay_in_full',
  'active',
  'usd',
  0,
  0,
  '{"validationFixture":true}'::jsonb
),
(
  'f4100000-0000-4000-8000-000000000102'::uuid,
  'stripe',
  'cs_validation_reality_candidate_2',
  'validation_reality_candidate',
  'Validation Reality Candidate Two',
  'pay_in_full',
  'active',
  'usd',
  0,
  0,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.implementation_cases(
  id,
  implementation_purchase_id,
  state,
  metadata
) values
(
  'f4100000-0000-4000-8000-000000000111'::uuid,
  'f4100000-0000-4000-8000-000000000101'::uuid,
  'in_implementation',
  '{"validationFixture":true}'::jsonb
),
(
  'f4100000-0000-4000-8000-000000000112'::uuid,
  'f4100000-0000-4000-8000-000000000102'::uuid,
  'in_implementation',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.implementation_threads(
  id,
  implementation_case_id,
  work_area,
  title,
  state,
  author_user_id
) values
(
  'f4100000-0000-4000-8000-000000000121'::uuid,
  'f4100000-0000-4000-8000-000000000111'::uuid,
  'people',
  'Reality Sentence validation thread',
  'open',
  'f4100000-0000-4000-8000-000000000191'::uuid
),
(
  'f4100000-0000-4000-8000-000000000122'::uuid,
  'f4100000-0000-4000-8000-000000000112'::uuid,
  'people',
  'Other case validation thread',
  'open',
  'f4100000-0000-4000-8000-000000000192'::uuid
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
  'f4100000-0000-4000-8000-000000000131'::uuid,
  'f4100000-0000-4000-8000-000000000111'::uuid,
  'people_authority',
  'Historical compatibility proposal',
  'Used only to verify that existing establishment-item custody survives the authority repair.',
  'proposed',
  'f4100000-0000-4000-8000-000000000191'::uuid,
  '{"validationFixture":true}'::jsonb
);
