-- Data-only production-schema-clone fixture for Ledger-custodied Expense Reporting v1.
-- Reporting objects do not exist yet; this fixture establishes only canonical
-- identity/Ledger/Spend/Evidence source reality that the candidate will interpret.

insert into auth.users(id)
values
  ('95359000-0000-4000-8000-000000000001'::uuid),
  ('95359000-0000-4000-8000-000000000002'::uuid);

insert into atlas.people(id,display_name,status,metadata)
values
  ('95359000-0000-4000-8000-000000000003'::uuid,'Expense Report Fixture Owner A','active','{"validation_fixture":true}'::jsonb),
  ('95359000-0000-4000-8000-000000000004'::uuid,'Expense Report Fixture Owner B','active','{"validation_fixture":true}'::jsonb);

insert into atlas.person_auth_credentials(id,person_id,auth_user_id,status,provenance)
values
  ('95359000-0000-4000-8000-000000000005'::uuid,'95359000-0000-4000-8000-000000000003'::uuid,'95359000-0000-4000-8000-000000000001'::uuid,'active','{"validation_fixture":true}'::jsonb),
  ('95359000-0000-4000-8000-000000000006'::uuid,'95359000-0000-4000-8000-000000000004'::uuid,'95359000-0000-4000-8000-000000000002'::uuid,'active','{"validation_fixture":true}'::jsonb);

insert into atlas.organizations(id,stable_key,name,status,metadata,onboarding_state)
values
  ('95359000-0000-4000-8000-000000000010'::uuid,'expense_report_fixture_org_a','Expense Report Fixture Organization A','active','{"validation_fixture":true}'::jsonb,'ready'),
  ('95359000-0000-4000-8000-000000000011'::uuid,'expense_report_fixture_org_b','Expense Report Fixture Organization B','active','{"validation_fixture":true}'::jsonb,'ready');

insert into atlas.organization_units(id,organization_id,stable_key,name,unit_kind,status,metadata)
values
  ('95359000-0000-4000-8000-000000000020'::uuid,'95359000-0000-4000-8000-000000000010'::uuid,'expense_report_fixture_unit_a','Expense Report Fixture Unit A','operating_unit','active','{"validation_fixture":true}'::jsonb);

insert into atlas.organization_memberships(id,organization_id,user_id,role,active,permissions,person_id)
values
  ('95359000-0000-4000-8000-000000000030'::uuid,'95359000-0000-4000-8000-000000000010'::uuid,'95359000-0000-4000-8000-000000000001'::uuid,'owner',true,'{}'::jsonb,'95359000-0000-4000-8000-000000000003'::uuid),
  ('95359000-0000-4000-8000-000000000031'::uuid,'95359000-0000-4000-8000-000000000011'::uuid,'95359000-0000-4000-8000-000000000002'::uuid,'owner',true,'{}'::jsonb,'95359000-0000-4000-8000-000000000004'::uuid);

insert into atlas.ledgers(id,stable_key,organization_id,ledger_kind,status,metadata,name)
values
  ('95359000-0000-4000-8000-000000000040'::uuid,'expense_report_fixture_ledger_a',null,'organization_governing','active','{"validation_fixture":true}'::jsonb,'Expense Report Fixture Ledger A'),
  ('95359000-0000-4000-8000-000000000041'::uuid,'expense_report_fixture_ledger_b',null,'organization_governing','active','{"validation_fixture":true}'::jsonb,'Expense Report Fixture Ledger B');

insert into atlas.ledger_organization_participations(id,ledger_id,organization_id,participation_kind,is_compatibility_primary,status,basis,metadata)
values
  ('95359000-0000-4000-8000-000000000042'::uuid,'95359000-0000-4000-8000-000000000040'::uuid,'95359000-0000-4000-8000-000000000010'::uuid,'governing',true,'active','{"validation_fixture":true}'::jsonb,'{"validation_fixture":true}'::jsonb),
  ('95359000-0000-4000-8000-000000000043'::uuid,'95359000-0000-4000-8000-000000000041'::uuid,'95359000-0000-4000-8000-000000000011'::uuid,'governing',true,'active','{"validation_fixture":true}'::jsonb,'{"validation_fixture":true}'::jsonb);

insert into atlas.principals(id,user_id,organization_id,stable_key,name,status,metadata,person_id)
values
  ('95359000-0000-4000-8000-000000000050'::uuid,'95359000-0000-4000-8000-000000000001'::uuid,'95359000-0000-4000-8000-000000000010'::uuid,'expense_report_fixture_principal_a','Expense Report Fixture Principal A','active','{"validation_fixture":true}'::jsonb,'95359000-0000-4000-8000-000000000003'::uuid),
  ('95359000-0000-4000-8000-000000000051'::uuid,'95359000-0000-4000-8000-000000000002'::uuid,'95359000-0000-4000-8000-000000000011'::uuid,'expense_report_fixture_principal_b','Expense Report Fixture Principal B','active','{"validation_fixture":true}'::jsonb,'95359000-0000-4000-8000-000000000004'::uuid);

insert into atlas.principal_ledger_authorities(id,principal_id,ledger_id,authority_kind,status,basis,metadata)
values
  ('95359000-0000-4000-8000-000000000052'::uuid,'95359000-0000-4000-8000-000000000050'::uuid,'95359000-0000-4000-8000-000000000040'::uuid,'root_governing','active','validation_fixture','{"validation_fixture":true}'::jsonb),
  ('95359000-0000-4000-8000-000000000053'::uuid,'95359000-0000-4000-8000-000000000051'::uuid,'95359000-0000-4000-8000-000000000041'::uuid,'root_governing','active','validation_fixture','{"validation_fixture":true}'::jsonb);

-- Canonical Spend A1: 1,650 MXN, member-funded accommodation.
insert into atlas.organization_spend_occurrences(
  id,ledger_id,organization_id,organization_unit_id,occurred_on,occurred_at,gross_amount,currency,
  funding_kind,payer_membership_id,payee_label,payment_method,source_kind,source_key,
  recorded_by_principal_id,recorded_by_membership_id,truth_state,provenance,metadata
)
values(
  '95359000-0000-4000-8000-000000000100'::uuid,
  '95359000-0000-4000-8000-000000000040'::uuid,
  '95359000-0000-4000-8000-000000000010'::uuid,
  '95359000-0000-4000-8000-000000000020'::uuid,
  '2026-09-15','2026-09-16 04:30:00+00',1650,'MXN','organization_member',
  '95359000-0000-4000-8000-000000000030'::uuid,
  'Fixture Hotel','personal_card','validation_fixture','expense-report-mxn-1',
  '95359000-0000-4000-8000-000000000050'::uuid,
  '95359000-0000-4000-8000-000000000030'::uuid,
  'confirmed','{"validation_fixture":true}'::jsonb,'{"validation_fixture":true}'::jsonb
);

insert into atlas.organization_spend_allocations(
  id,ledger_id,organization_id,spend_occurrence_id,organization_unit_id,allocated_amount,
  operational_purpose,recorded_by_principal_id,recorded_by_membership_id,provenance,metadata
)
values(
  '95359000-0000-4000-8000-000000000101'::uuid,
  '95359000-0000-4000-8000-000000000040'::uuid,
  '95359000-0000-4000-8000-000000000010'::uuid,
  '95359000-0000-4000-8000-000000000100'::uuid,
  '95359000-0000-4000-8000-000000000020'::uuid,
  1650,'Accommodation for program travel',
  '95359000-0000-4000-8000-000000000050'::uuid,
  '95359000-0000-4000-8000-000000000030'::uuid,
  '{"validation_fixture":true}'::jsonb,'{"validation_fixture":true}'::jsonb
);

-- Canonical Spend A2: $50 organization-funded goodwill.
insert into atlas.organization_spend_occurrences(
  id,ledger_id,organization_id,organization_unit_id,occurred_on,gross_amount,currency,
  funding_kind,payee_label,payment_method,source_kind,source_key,
  recorded_by_principal_id,recorded_by_membership_id,truth_state,provenance,metadata
)
values(
  '95359000-0000-4000-8000-000000000102'::uuid,
  '95359000-0000-4000-8000-000000000040'::uuid,
  '95359000-0000-4000-8000-000000000010'::uuid,
  '95359000-0000-4000-8000-000000000020'::uuid,
  '2026-09-16',50,'USD','organization','Fixture Community Vendor','organization_card',
  'validation_fixture','expense-report-usd-1',
  '95359000-0000-4000-8000-000000000050'::uuid,
  '95359000-0000-4000-8000-000000000030'::uuid,
  'confirmed','{"validation_fixture":true}'::jsonb,'{"validation_fixture":true}'::jsonb
);

insert into atlas.organization_spend_allocations(
  id,ledger_id,organization_id,spend_occurrence_id,organization_unit_id,allocated_amount,
  operational_purpose,recorded_by_principal_id,recorded_by_membership_id,provenance,metadata
)
values(
  '95359000-0000-4000-8000-000000000103'::uuid,
  '95359000-0000-4000-8000-000000000040'::uuid,
  '95359000-0000-4000-8000-000000000010'::uuid,
  '95359000-0000-4000-8000-000000000102'::uuid,
  '95359000-0000-4000-8000-000000000020'::uuid,
  50,'Community goodwill',
  '95359000-0000-4000-8000-000000000050'::uuid,
  '95359000-0000-4000-8000-000000000030'::uuid,
  '{"validation_fixture":true}'::jsonb,'{"validation_fixture":true}'::jsonb
);

-- Foreign Spend B for custody rejection proof.
insert into atlas.organization_spend_occurrences(
  id,ledger_id,organization_id,occurred_on,gross_amount,currency,funding_kind,payee_label,
  source_kind,source_key,recorded_by_principal_id,recorded_by_membership_id,truth_state,provenance,metadata
)
values(
  '95359000-0000-4000-8000-000000000120'::uuid,
  '95359000-0000-4000-8000-000000000041'::uuid,
  '95359000-0000-4000-8000-000000000011'::uuid,
  '2026-09-15',25,'USD','organization','Foreign Fixture Vendor',
  'validation_fixture','expense-report-foreign-1',
  '95359000-0000-4000-8000-000000000051'::uuid,
  '95359000-0000-4000-8000-000000000031'::uuid,
  'confirmed','{"validation_fixture":true}'::jsonb,'{"validation_fixture":true}'::jsonb
);

insert into atlas.organization_spend_allocations(
  id,ledger_id,organization_id,spend_occurrence_id,allocated_amount,operational_purpose,
  recorded_by_principal_id,recorded_by_membership_id,provenance,metadata
)
values(
  '95359000-0000-4000-8000-000000000121'::uuid,
  '95359000-0000-4000-8000-000000000041'::uuid,
  '95359000-0000-4000-8000-000000000011'::uuid,
  '95359000-0000-4000-8000-000000000120'::uuid,
  25,'Foreign purpose',
  '95359000-0000-4000-8000-000000000051'::uuid,
  '95359000-0000-4000-8000-000000000031'::uuid,
  '{"validation_fixture":true}'::jsonb,'{"validation_fixture":true}'::jsonb
);

-- Canonical receipt Evidence exists, but is not linked to Spend until a postcondition
-- deliberately establishes that consequence.
insert into atlas.evidence_records(
  id,scope_kind,scope_id,subject_domain,subject_kind,subject_id,evidence_kind,
  source_kind,source_key,actor_user_id,value,confidence,observed_at,provenance,metadata
)
values(
  '95359000-0000-4000-8000-000000000130'::uuid,
  'principal','95359000-0000-4000-8000-000000000050'::uuid,
  'finance','receipt','expense-report-receipt-a','document',
  'validation_fixture','expense-report-receipt-a',
  '95359000-0000-4000-8000-000000000001'::uuid,
  '{"amount":1650,"currency":"MXN","document":"fixture receipt"}'::jsonb,
  1,'2026-09-15 17:30:00+00','{"validation_fixture":true}'::jsonb,'{"validation_fixture":true}'::jsonb
);
