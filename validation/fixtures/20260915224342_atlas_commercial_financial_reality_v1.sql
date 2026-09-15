-- Data-only production-schema-clone fixture for Commercial Financial Reality v1.
-- One historical physical Organization carries both a canonical-reassigned farm
-- and an archived test farm, matching the production custody shape this tranche
-- must respect.

insert into auth.users(id)
values ('95224342-0000-4000-8000-000000000001'::uuid);

insert into atlas.people(id,stable_key,display_name,status,metadata)
values (
  '95224342-0000-4000-8000-000000000002'::uuid,
  'commercial_financial_fixture_person',
  'Commercial Financial Fixture Owner',
  'active',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.person_auth_credentials(id,person_id,auth_user_id,status,provenance)
values (
  '95224342-0000-4000-8000-000000000003'::uuid,
  '95224342-0000-4000-8000-000000000002'::uuid,
  '95224342-0000-4000-8000-000000000001'::uuid,
  'active',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.organizations(id,stable_key,name,status,metadata,onboarding_state)
values
(
  '95224342-0000-4000-8000-000000000010'::uuid,
  'commercial_financial_fixture_historical_org',
  'Commercial Financial Historical Carrier',
  'active',
  '{"validation_fixture":true}'::jsonb,
  'ready'
),
(
  '95224342-0000-4000-8000-000000000011'::uuid,
  'commercial_financial_fixture_canonical_org',
  'Commercial Financial Canonical Organization',
  'active',
  '{"validation_fixture":true}'::jsonb,
  'ready'
);

insert into atlas.organization_units(id,organization_id,stable_key,name,unit_kind,status,metadata)
values
(
  '95224342-0000-4000-8000-000000000020'::uuid,
  '95224342-0000-4000-8000-000000000010'::uuid,
  'commercial_financial_fixture_real_unit',
  'Commercial Financial Real Unit',
  'operating_unit',
  'active',
  '{"validation_fixture":true}'::jsonb
),
(
  '95224342-0000-4000-8000-000000000021'::uuid,
  '95224342-0000-4000-8000-000000000010'::uuid,
  'commercial_financial_fixture_test_unit',
  'Commercial Financial Test Unit',
  'operating_unit',
  'active',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.farms(id,organization_id,organization_unit_id,stable_key,name,status,metadata)
values
(
  '95224342-0000-4000-8000-000000000030'::uuid,
  '95224342-0000-4000-8000-000000000010'::uuid,
  '95224342-0000-4000-8000-000000000020'::uuid,
  'commercial_financial_fixture_real_farm',
  'Commercial Financial Real Farm',
  'active',
  '{"validation_fixture":true}'::jsonb
),
(
  '95224342-0000-4000-8000-000000000031'::uuid,
  '95224342-0000-4000-8000-000000000010'::uuid,
  '95224342-0000-4000-8000-000000000021'::uuid,
  'commercial_financial_fixture_test_farm',
  'Commercial Financial Test Farm',
  'active',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.farm_memberships(id,user_id,farm_id,role,active,permissions)
values
(
  '95224342-0000-4000-8000-000000000040'::uuid,
  '95224342-0000-4000-8000-000000000001'::uuid,
  '95224342-0000-4000-8000-000000000030'::uuid,
  'owner',true,'{}'::jsonb
),
(
  '95224342-0000-4000-8000-000000000041'::uuid,
  '95224342-0000-4000-8000-000000000001'::uuid,
  '95224342-0000-4000-8000-000000000031'::uuid,
  'owner',true,'{}'::jsonb
);

insert into atlas.ledgers(id,stable_key,organization_id,ledger_kind,status,metadata,name)
values (
  '95224342-0000-4000-8000-000000000050'::uuid,
  'commercial_financial_fixture_canonical_ledger',
  '95224342-0000-4000-8000-000000000011'::uuid,
  'organization_governing',
  'active',
  '{"validation_fixture":true}'::jsonb,
  'Commercial Financial Canonical Ledger'
);

insert into atlas.principals(id,user_id,organization_id,stable_key,name,status,metadata,person_id)
values (
  '95224342-0000-4000-8000-000000000060'::uuid,
  '95224342-0000-4000-8000-000000000001'::uuid,
  '95224342-0000-4000-8000-000000000011'::uuid,
  'commercial_financial_fixture_principal',
  'Commercial Financial Fixture Principal',
  'active',
  '{"validation_fixture":true}'::jsonb,
  '95224342-0000-4000-8000-000000000002'::uuid
);

insert into atlas.principal_ledger_authorities(id,principal_id,ledger_id,authority_kind,status,basis,metadata)
values (
  '95224342-0000-4000-8000-000000000061'::uuid,
  '95224342-0000-4000-8000-000000000060'::uuid,
  '95224342-0000-4000-8000-000000000050'::uuid,
  'root_governing',
  'active',
  'validation_fixture',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.institutional_custody_adjudications(
  id,subject_schema,subject_table,subject_key,disposition,
  historical_organization_id,canonical_organization_id,canonical_ledger_id,
  evidence_basis,evidence,metadata
)
values
(
  '95224342-0000-4000-8000-000000000070'::uuid,
  'atlas','farms','95224342-0000-4000-8000-000000000030','reassigned',
  '95224342-0000-4000-8000-000000000010'::uuid,
  '95224342-0000-4000-8000-000000000011'::uuid,
  '95224342-0000-4000-8000-000000000050'::uuid,
  'validation_canonical_farm',
  '{"validation_fixture":true}'::jsonb,
  '{}'::jsonb
),
(
  '95224342-0000-4000-8000-000000000071'::uuid,
  'atlas','farms','95224342-0000-4000-8000-000000000031','archived',
  '95224342-0000-4000-8000-000000000010'::uuid,
  null,
  null,
  'waiting_room_test_scope',
  '{"validation_fixture":true,"physicalRowPreserved":true}'::jsonb,
  '{}'::jsonb
);

insert into atlas.flower_sale_orders(
  id,farm_id,buyer_relationship_id,customer_label,sales_channel,event_key,sale_date,
  fulfillment_mode,fulfillment_due_date,fulfillment_due_time,fulfillment_membership_id,
  subtotal_amount,tax_amount,tip_amount,total_amount,currency,source_task_id,note,
  idempotency_key,recorded_by_membership_id,created_by_user_id,metadata
)
values
(
  '95224342-0000-4000-8000-000000000080'::uuid,
  '95224342-0000-4000-8000-000000000030'::uuid,
  null,'Fixture Florist','wholesale',null,'2026-09-15',
  'immediate_handoff',null,null,null,
  25.00,0,0,25.00,'USD',null,'Historical sale with unknown collection truth.',
  'commercial-financial-fixture-real-sale','95224342-0000-4000-8000-000000000040'::uuid,
  '95224342-0000-4000-8000-000000000001'::uuid,
  '{"validation_fixture":true}'::jsonb
),
(
  '95224342-0000-4000-8000-000000000081'::uuid,
  '95224342-0000-4000-8000-000000000031'::uuid,
  null,'TEST — Fixture Buyer','wholesale',null,'2026-09-15',
  'immediate_handoff',null,null,null,
  12.34,0,0,12.34,'USD',null,'Archived test-scope sale; never canonical money.',
  'commercial-financial-fixture-test-sale','95224342-0000-4000-8000-000000000041'::uuid,
  '95224342-0000-4000-8000-000000000001'::uuid,
  '{"validation_fixture":true}'::jsonb
);

-- Mirrors production: the historical real Flower Sale already has a universal
-- Commercial Order bridge, while the archived test Sale intentionally does not.
insert into atlas.commercial_orders(
  id,organization_id,organization_unit_id,customer_relationship_id,customer_subject_id,
  order_kind,order_date,channel,subtotal_amount,tax_amount,tip_amount,total_amount,
  currency,idempotency_key,note,metadata,created_at
)
values (
  '95224342-0000-4000-8000-000000000082'::uuid,
  '95224342-0000-4000-8000-000000000010'::uuid,
  '95224342-0000-4000-8000-000000000020'::uuid,
  null,null,'sale','2026-09-15','wholesale',25.00,0,0,25.00,'USD',
  'legacy_flower_sale_order:95224342-0000-4000-8000-000000000080',
  'Historical universal bridge.',
  '{"sourceDomain":"flower","legacyFlowerSaleOrderId":"95224342-0000-4000-8000-000000000080","farmId":"95224342-0000-4000-8000-000000000030","validation_fixture":true}'::jsonb,
  '2026-09-15 12:00:00+00'
);

insert into atlas.commercial_order_events(
  commercial_order_id,event_kind,occurred_at,idempotency_key,metadata
)
values (
  '95224342-0000-4000-8000-000000000082'::uuid,
  'recorded','2026-09-15 12:00:00+00',
  'legacy_flower_sale_recorded:95224342-0000-4000-8000-000000000080',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.flower_commercial_order_extensions(
  flower_sale_order_id,commercial_order_id,farm_id,metadata
)
values (
  '95224342-0000-4000-8000-000000000080'::uuid,
  '95224342-0000-4000-8000-000000000082'::uuid,
  '95224342-0000-4000-8000-000000000030'::uuid,
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.community_programs(
  id,farm_id,stable_key,title,active,timezone_name,cadence,metadata,created_by_user_id
)
values (
  '95224342-0000-4000-8000-000000000090'::uuid,
  '95224342-0000-4000-8000-000000000030'::uuid,
  'commercial_financial_fixture_program',
  'Commercial Financial Fixture Program',
  true,'America/Chicago','{}'::jsonb,'{"validation_fixture":true}'::jsonb,
  '95224342-0000-4000-8000-000000000001'::uuid
);

insert into atlas.community_registration_offerings(
  id,farm_id,program_id,event_id,stable_key,title,registration_type,status,
  opens_at,closes_at,fee_amount,fee_currency,fee_basis,registration_scope,
  public_description,terms_version,metadata
)
values (
  '95224342-0000-4000-8000-000000000091'::uuid,
  '95224342-0000-4000-8000-000000000030'::uuid,
  '95224342-0000-4000-8000-000000000090'::uuid,
  null,
  'commercial_financial_fixture_registration',
  'Commercial Financial Fixture Registration',
  'household_participation','open',
  null,null,60.00,'USD','per_household','entire_program',
  'Validation registration.','fixture-v1','{"validation_fixture":true}'::jsonb
);

insert into atlas.community_registrations(
  id,offering_id,registration_number,registrant_type,status,primary_name,primary_email,
  primary_phone,household_name,submitted_at,confirmed_at,cancelled_at,metadata
)
values (
  '95224342-0000-4000-8000-000000000092'::uuid,
  '95224342-0000-4000-8000-000000000091'::uuid,
  'FIXTURE-CFR-0001','household','confirmed','Fixture Registrant','fixture@example.test',
  null,'Fixture Household','2026-09-15 12:00:00+00','2026-09-15 12:05:00+00',null,
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.community_registration_payments(
  id,registration_id,amount,currency,status,payment_processor,external_payment_id,
  paid_at,refunded_at,beneficiary_type,beneficiary_reference,metadata
)
values (
  '95224342-0000-4000-8000-000000000093'::uuid,
  '95224342-0000-4000-8000-000000000092'::uuid,
  60.00,'USD','paid','stripe','pi_fixture_commercial_financial',
  '2026-09-15 12:05:00+00',null,null,null,
  '{"validation_fixture":true}'::jsonb
);
