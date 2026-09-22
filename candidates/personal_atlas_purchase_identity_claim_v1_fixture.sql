insert into auth.users(id,email,created_at,updated_at)
values
  ('f6e10000-0000-4000-8000-000000000001'::uuid,'atlas-human@example.invalid',now(),now()),
  ('f6e10000-0000-4000-8000-000000000002'::uuid,'other-human@example.invalid',now(),now());

insert into atlas.personal_atlas_purchases(
  id,provider,provider_checkout_session_id,provider_subscription_id,
  purchaser_email,offer_key,purchase_state,purchased_at,metadata
) values (
  'f6e10000-0000-4000-8000-000000000010'::uuid,
  'stripe',
  'cs_validation_personal_purchase_identity_claim_v1',
  'sub_validation_personal_purchase_identity_claim_v1',
  'payer@example.invalid',
  'personal_atlas',
  'active',
  now(),
  '{"validationFixture":true}'::jsonb
);
