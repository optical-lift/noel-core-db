-- Data-only production-shaped fixture for Package 5 Money Collection current-main v1.
-- Creates one canonical farm, one archived test farm, one positive Flower Sale,
-- one test Flower Sale, and one paid Community Registration.

insert into auth.users(id,email)
values ('95154000-0000-4000-8000-000000000001'::uuid,'money.fixture@example.test');

insert into atlas.organizations(id,stable_key,name,status,metadata,onboarding_state)
values (
  '95154000-0000-4000-8000-000000000010'::uuid,
  'money_fixture_org',
  'Money Fixture Organization',
  'active',
  '{"validation_fixture":true}'::jsonb,
  'ready'
);

insert into atlas.organization_memberships(id,organization_id,user_id,role,active,permissions)
values (
  '95154000-0000-4000-8000-000000000011'::uuid,
  '95154000-0000-4000-8000-000000000010'::uuid,
  '95154000-0000-4000-8000-000000000001'::uuid,
  'owner',
  true,
  '{}'::jsonb
);

insert into atlas.farms(id,organization_id,stable_key,name,status,metadata)
values
(
  '95154000-0000-4000-8000-000000000020'::uuid,
  '95154000-0000-4000-8000-000000000010'::uuid,
  'money_fixture_canonical_farm',
  'Money Fixture Canonical Farm',
  'active',
  '{"validation_fixture":true}'::jsonb
),
(
  '95154000-0000-4000-8000-000000000021'::uuid,
  '95154000-0000-4000-8000-000000000010'::uuid,
  'money_fixture_archived_farm',
  'Money Fixture Archived Farm',
  'active',
  '{"validation_fixture":true,"testMode":true}'::jsonb
);

insert into atlas.farm_memberships(id,user_id,farm_id,role,active,permissions)
values
(
  '95154000-0000-4000-8000-000000000030'::uuid,
  '95154000-0000-4000-8000-000000000001'::uuid,
  '95154000-0000-4000-8000-000000000020'::uuid,
  'owner',
  true,
  '{}'::jsonb
),
(
  '95154000-0000-4000-8000-000000000031'::uuid,
  '95154000-0000-4000-8000-000000000001'::uuid,
  '95154000-0000-4000-8000-000000000021'::uuid,
  'owner',
  true,
  '{}'::jsonb
);

insert into atlas.institutional_custody_adjudications(
  subject_schema,subject_table,subject_key,disposition,
  historical_organization_id,evidence_basis,evidence
)
values (
  'atlas','farms','95154000-0000-4000-8000-000000000021','archived',
  '95154000-0000-4000-8000-000000000010'::uuid,
  'money_validation_archived_test_scope',
  '{"validation_fixture":true,"testMode":true}'::jsonb
);

insert into atlas.flower_sale_orders(
  id,farm_id,customer_label,sales_channel,sale_date,fulfillment_mode,
  subtotal_amount,tax_amount,tip_amount,total_amount,currency,
  note,idempotency_key,recorded_by_membership_id,metadata,created_at
)
values
(
  '95154000-0000-4000-8000-000000000040'::uuid,
  '95154000-0000-4000-8000-000000000020'::uuid,
  'Money Fixture Buyer',
  'wholesale',
  '2026-09-15'::date,
  'immediate_handoff',
  25.00,0,0,25.00,'USD',
  'Canonical Money fixture sale',
  'money-fixture:canonical-sale',
  '95154000-0000-4000-8000-000000000030'::uuid,
  '{"validation_fixture":true}'::jsonb,
  '2026-09-15T12:00:00-05'::timestamptz
),
(
  '95154000-0000-4000-8000-000000000041'::uuid,
  '95154000-0000-4000-8000-000000000021'::uuid,
  'TEST — Money Fixture Buyer',
  'wholesale',
  '2026-09-15'::date,
  'immediate_handoff',
  12.34,0,0,12.34,'USD',
  '[TEST ONLY] Archived scope must not become Money.',
  'money-fixture:archived-test-sale',
  '95154000-0000-4000-8000-000000000031'::uuid,
  '{"validation_fixture":true,"testMode":true}'::jsonb,
  '2026-09-15T12:05:00-05'::timestamptz
);

insert into atlas.community_programs(
  id,farm_id,stable_key,title,active,timezone_name,cadence,metadata,created_by_user_id
)
values (
  '95154000-0000-4000-8000-000000000050'::uuid,
  '95154000-0000-4000-8000-000000000020'::uuid,
  'money_fixture_program',
  'Money Fixture Program',
  true,
  'America/Chicago',
  '{}'::jsonb,
  '{"validation_fixture":true}'::jsonb,
  '95154000-0000-4000-8000-000000000001'::uuid
);

insert into atlas.community_registration_offerings(
  id,farm_id,program_id,stable_key,title,registration_type,status,
  fee_amount,fee_currency,fee_basis,registration_scope,metadata
)
values (
  '95154000-0000-4000-8000-000000000051'::uuid,
  '95154000-0000-4000-8000-000000000020'::uuid,
  '95154000-0000-4000-8000-000000000050'::uuid,
  'money_fixture_paid_offering',
  'Money Fixture Paid Offering',
  'household_participation',
  'open',
  60.00,
  'USD',
  'per_household',
  'entire_program',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.community_registrations(
  id,offering_id,registration_number,registrant_type,status,
  primary_name,primary_email,submitted_at,confirmed_at,metadata,created_at
)
values (
  '95154000-0000-4000-8000-000000000052'::uuid,
  '95154000-0000-4000-8000-000000000051'::uuid,
  'MONEY-FIXTURE-001',
  'household',
  'confirmed',
  'Money Fixture Household',
  'money.household@example.test',
  '2026-09-15T12:10:00-05'::timestamptz,
  '2026-09-15T12:15:00-05'::timestamptz,
  '{"validation_fixture":true}'::jsonb,
  '2026-09-15T12:10:00-05'::timestamptz
);

insert into atlas.community_registration_payments(
  id,registration_id,amount,currency,status,payment_processor,
  external_payment_id,paid_at,metadata,created_at
)
values (
  '95154000-0000-4000-8000-000000000053'::uuid,
  '95154000-0000-4000-8000-000000000052'::uuid,
  60.00,
  'USD',
  'paid',
  'stripe',
  'pi_money_fixture_001',
  '2026-09-15T12:15:00-05'::timestamptz,
  '{"validation_fixture":true,"evidenceSource":"historical_admitted_payment"}'::jsonb,
  '2026-09-15T12:15:00-05'::timestamptz
);
