-- DML-only prerequisites for Atlas Notebook Exposure Reconciliation v1 clone proof.

insert into auth.users(id,email,created_at,updated_at)
values
  ('c1111111-1111-4111-8111-111111111111'::uuid,'notebook-reconcile-life@example.test',now(),now()),
  ('c2222222-2222-4222-8222-222222222222'::uuid,'notebook-reconcile-ledger@example.test',now(),now());

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
    'cs_notebook_reconcile_life',
    'sub_notebook_reconcile_life',
    'notebook-reconcile-life@example.test',
    'personal_atlas',
    'active',
    now(),
    '{}'::jsonb
  ),
  (
    'stripe',
    'cs_notebook_reconcile_ledger',
    'sub_notebook_reconcile_ledger',
    'notebook-reconcile-ledger@example.test',
    'personal_atlas',
    'active',
    now(),
    '{}'::jsonb
  );
