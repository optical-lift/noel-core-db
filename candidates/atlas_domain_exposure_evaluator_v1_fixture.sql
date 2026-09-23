-- DML-only prerequisites for Atlas Domain Exposure Evaluator v1 clone proof.

insert into auth.users(id,email,created_at,updated_at)
values
  ('a1111111-1111-4111-8111-111111111111'::uuid,'domain-exposure-life@example.test',now(),now()),
  ('a2222222-2222-4222-8222-222222222222'::uuid,'domain-exposure-ledger@example.test',now(),now()),
  ('a3333333-3333-4333-8333-333333333333'::uuid,'domain-exposure-no-person@example.test',now(),now());

insert into atlas.personal_atlas_purchases(
  provider,
  provider_checkout_session_id,
  provider_subscription_id,
  purchaser_email,
  offer_key,
  purchase_state,
  purchased_at,
  metadata
) values
  (
    'stripe',
    'cs_domain_exposure_life',
    'sub_domain_exposure_life',
    'domain-exposure-life@example.test',
    'personal_atlas',
    'active',
    now(),
    '{}'::jsonb
  ),
  (
    'stripe',
    'cs_domain_exposure_ledger',
    'sub_domain_exposure_ledger',
    'domain-exposure-ledger@example.test',
    'personal_atlas',
    'active',
    now(),
    '{}'::jsonb
  );
