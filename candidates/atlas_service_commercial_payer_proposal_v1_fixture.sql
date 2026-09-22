-- Clone-only fixture for Atlas Service Commercial Payer Proposal v1.
-- Parent Commercial Composition v1 is expected to be live before this migration.

insert into auth.users(id,email,created_at,updated_at)
values (
  'f4e00000-0000-4000-8000-000000000001'::uuid,
  'payer-proposal-proof@example.invalid',
  now(),now()
);
