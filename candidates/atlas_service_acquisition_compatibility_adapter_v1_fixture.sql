insert into atlas.atlas_service_commercial_price_policies(
  price_key,item_kind,charge_kind,unit_amount_cents,currency,billing_interval,
  requires_explicit_election,policy_status,effective_from,source_note,metadata
) values
(
  'atlas-initial-setup-legacy-v1',
  'atlas_initial_setup','one_time',3995,'USD',null,
  false,'transitional','2026-09-01',
  'Validation copy of the production Personal Atlas setup policy required by acquisition compatibility reconciliation.',
  '{"source":"validation_fixture_from_live_price_policy"}'::jsonb
),
(
  'atlas-base-monthly-v1',
  'atlas_base_recurring','recurring',700,'USD','month',
  false,'active','2026-09-01',
  'Validation copy of the production base Atlas monthly policy required by acquisition compatibility reconciliation.',
  '{"source":"validation_fixture_from_live_price_policy"}'::jsonb
)
on conflict(price_key) do nothing;

insert into auth.users(id,email,created_at,updated_at)
values (
  'a5c10000-0000-4000-8000-000000000001'::uuid,
  'acquisition-compat-personal@example.invalid',
  now(),now()
);

insert into atlas.personal_atlas_purchases(
  id,provider,provider_checkout_session_id,provider_subscription_id,
  purchaser_email,offer_key,purchase_state,purchased_at,
  claimed_by_user_id,metadata
) values (
  'a5c10000-0000-4000-8000-000000000011'::uuid,
  'stripe',
  'cs_acquisition_compat_personal',
  'sub_acquisition_compat_personal',
  'acquisition-compat-personal@example.invalid',
  'personal_atlas',
  'active',
  '2026-09-22T12:00:00Z'::timestamptz,
  'a5c10000-0000-4000-8000-000000000001'::uuid,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.implementation_purchases(
  id,provider,provider_checkout_session_id,provider_subscription_id,
  offer_key,starting_label,payment_option,purchase_state,currency,
  setup_contract_amount_cents,monthly_ledger_unit_price_cents,
  recurring_starts_at,purchased_at,metadata
) values (
  'a5c10000-0000-4000-8000-000000000021'::uuid,
  'stripe',
  'cs_acquisition_compat_implementation',
  'sub_acquisition_compat_implementation',
  'standard_organization',
  'Compatibility Proof Organization',
  'three_installments',
  'active',
  'usd',
  300000,
  40000,
  '2026-10-22T12:00:00Z'::timestamptz,
  '2026-09-22T12:05:00Z'::timestamptz,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.implementation_cases(
  id,implementation_purchase_id,state,metadata
) values (
  'a5c10000-0000-4000-8000-000000000022'::uuid,
  'a5c10000-0000-4000-8000-000000000021'::uuid,
  'awaiting_setup_human',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.ledger_entitlements(
  id,implementation_case_id,source_purchase_id,entitlement_number,
  entitlement_kind,price_class,state,setup_price_cents,monthly_price_cents,
  recurring_starts_at,purchased_at,commercial_basis,metadata
) values (
  'a5c10000-0000-4000-8000-000000000023'::uuid,
  'a5c10000-0000-4000-8000-000000000022'::uuid,
  'a5c10000-0000-4000-8000-000000000021'::uuid,
  1,
  'atlas_ledger',
  'baseline_first',
  'available',
  300000,
  40000,
  '2026-10-22T12:00:00Z'::timestamptz,
  '2026-09-22T12:05:00Z'::timestamptz,
  '{"source":"validation_fixture"}'::jsonb,
  '{"validationFixture":true}'::jsonb
);
