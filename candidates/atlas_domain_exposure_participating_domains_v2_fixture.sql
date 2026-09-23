-- DML-only prerequisites for Atlas Domain Exposure participating domains v2 clone proof.

insert into auth.users(id,email,created_at,updated_at)
values
  ('c1111111-1111-4111-8111-111111111111'::uuid,'domain-exposure-household-v2@example.test',now(),now()),
  ('c2222222-2222-4222-8222-222222222222'::uuid,'domain-exposure-flower-v2@example.test',now(),now()),
  ('c3333333-3333-4333-8333-333333333333'::uuid,'domain-exposure-correspondence-v2@example.test',now(),now());

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
    'stripe','cs_domain_exposure_household_v2','sub_domain_exposure_household_v2',
    'domain-exposure-household-v2@example.test','personal_atlas','active',now(),'{}'::jsonb
  ),
  (
    'stripe','cs_domain_exposure_flower_v2','sub_domain_exposure_flower_v2',
    'domain-exposure-flower-v2@example.test','personal_atlas','active',now(),'{}'::jsonb
  ),
  (
    'stripe','cs_domain_exposure_correspondence_v2','sub_domain_exposure_correspondence_v2',
    'domain-exposure-correspondence-v2@example.test','personal_atlas','active',now(),'{}'::jsonb
  );
