-- DML-only prerequisites for Atlas Notebook Exposure Admission v1 clone proof.

insert into auth.users(id,email,created_at,updated_at)
values
  ('b1111111-1111-4111-8111-111111111111'::uuid,'notebook-admission-life@example.test',now(),now()),
  ('b2222222-2222-4222-8222-222222222222'::uuid,'notebook-admission-ledger@example.test',now(),now());

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
    'cs_notebook_admission_life',
    'sub_notebook_admission_life',
    'notebook-admission-life@example.test',
    'personal_atlas',
    'active',
    now(),
    '{}'::jsonb
  ),
  (
    'stripe',
    'cs_notebook_admission_ledger',
    'sub_notebook_admission_ledger',
    'notebook-admission-ledger@example.test',
    'personal_atlas',
    'active',
    now(),
    '{}'::jsonb
  );
