-- DML-only prerequisite fixture for Atlas Person Position Self Projection v0.
-- Seeds only credential and purchase prerequisites. Behavioral construction stays in postconditions.

insert into auth.users(id,email,created_at,updated_at)
values
  ('91111111-1111-4111-8111-111111111111'::uuid,'person-position-personal@example.test',now(),now()),
  ('92222222-2222-4222-8222-222222222222'::uuid,'person-position-one-org@example.test',now(),now()),
  ('93333333-3333-4333-8333-333333333333'::uuid,'person-position-multi-org@example.test',now(),now()),
  ('94444444-4444-4444-8444-444444444444'::uuid,'person-position-no-person@example.test',now(),now());

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
    'cs_person_position_personal',
    'sub_person_position_personal',
    'person-position-personal@example.test',
    'personal_atlas',
    'active',
    now(),
    '{}'::jsonb
  ),
  (
    'stripe',
    'cs_person_position_one_org',
    'sub_person_position_one_org',
    'person-position-one-org@example.test',
    'personal_atlas',
    'active',
    now(),
    '{}'::jsonb
  ),
  (
    'stripe',
    'cs_person_position_multi_org',
    'sub_person_position_multi_org',
    'person-position-multi-org@example.test',
    'personal_atlas',
    'active',
    now(),
    '{}'::jsonb
  );
