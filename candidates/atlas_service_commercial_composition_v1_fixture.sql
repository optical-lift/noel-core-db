-- Clone-only fixture for Atlas Service Commercial Composition v1.
-- Builds one authenticated journey before Principal identity exists.
-- No purchase, entitlement, Organization, or generic Commercial Order is created.

insert into auth.users(id,email,created_at,updated_at)
values (
  'f4d00000-0000-4000-8000-000000000001'::uuid,
  'composition-proof@example.invalid',
  now(),now()
);
