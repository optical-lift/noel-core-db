-- Data-only fixture for Atlas Commercial Ledger Binding v1.
-- Creates pre-existing governed Ledgers plus implementation commerce around them.

insert into auth.users(id)
values
  ('11111111-1111-4111-8111-111111111111'::uuid),
  ('22222222-2222-4222-8222-222222222221'::uuid),
  ('33333333-3333-4333-8333-333333333331'::uuid);

-- Two sponsor Principals. Principal compatibility establishes Canonical Person bindings.
insert into atlas.principals(
  id,user_id,organization_id,stable_key,name,home_timezone,status,metadata
) values
(
  '11111111-1111-4111-8111-111111111112'::uuid,
  '11111111-1111-4111-8111-111111111111'::uuid,
  null,
  'commercial_binding_fixture_principal_one',
  'Commercial Binding Fixture Principal One',
  'America/Chicago','active','{"validation_fixture":true}'::jsonb
),
(
  '22222222-2222-4222-8222-222222222222'::uuid,
  '22222222-2222-4222-8222-222222222221'::uuid,
  null,
  'commercial_binding_fixture_principal_two',
  'Commercial Binding Fixture Principal Two',
  'America/Chicago','active','{"validation_fixture":true}'::jsonb
);

insert into atlas.implementation_practitioners(
  human_user_id,status,authorization_basis,metadata
) values (
  '33333333-3333-4333-8333-333333333331'::uuid,
  'active',
  '{"basis":"validation_fixture"}'::jsonb,
  '{"validation_fixture":true}'::jsonb
);

-- Establish three institutional targets before any implementation purchase can bind to them.
do $fixture$
declare
  v_person_one uuid;
  v_person_two uuid;
begin
  select person_id into v_person_one
  from atlas.person_auth_credentials
  where auth_user_id='11111111-1111-4111-8111-111111111111'::uuid and status='active'
  limit 1;

  select person_id into v_person_two
  from atlas.person_auth_credentials
  where auth_user_id='22222222-2222-4222-8222-222222222221'::uuid and status='active'
  limit 1;

  perform atlas.establish_organization_ledger_for_principal_v1(
    '11111111-1111-4111-8111-111111111112'::uuid,
    v_person_one,
    null,
    'Commercial Binding Target A',
    false,false,'commercial_binding_validation_fixture'
  );

  perform atlas.establish_organization_ledger_for_principal_v1(
    '11111111-1111-4111-8111-111111111112'::uuid,
    v_person_one,
    null,
    'Commercial Binding Target C',
    false,false,'commercial_binding_validation_fixture'
  );

  perform atlas.establish_organization_ledger_for_principal_v1(
    '22222222-2222-4222-8222-222222222222'::uuid,
    v_person_two,
    null,
    'Commercial Binding Target B',
    false,false,'commercial_binding_validation_fixture'
  );
end;
$fixture$;

-- Four implementation cases support success plus negative-path proofs.
insert into atlas.implementation_purchases(
  id,provider_checkout_session_id,offer_key,starting_label,payment_option,purchase_state,
  currency,setup_contract_amount_cents,monthly_ledger_unit_price_cents,metadata
) values
('44444444-4444-4444-8444-444444444401'::uuid,'fixture-checkout-1','fixture-offer','Fixture One','pay_in_full','active','usd',300000,40000,'{"validation_fixture":true}'::jsonb),
('55555555-5555-4555-8555-555555555501'::uuid,'fixture-checkout-2','fixture-offer','Fixture Two','pay_in_full','active','usd',300000,40000,'{"validation_fixture":true}'::jsonb),
('66666666-6666-4666-8666-666666666601'::uuid,'fixture-checkout-3','fixture-offer','Fixture Three','pay_in_full','active','usd',300000,40000,'{"validation_fixture":true}'::jsonb),
('77777777-7777-4777-8777-777777777701'::uuid,'fixture-checkout-4','fixture-offer','Fixture Four','pay_in_full','active','usd',300000,40000,'{"validation_fixture":true}'::jsonb);

insert into atlas.implementation_cases(id,implementation_purchase_id,state,metadata)
values
('44444444-4444-4444-8444-444444444411'::uuid,'44444444-4444-4444-8444-444444444401'::uuid,'in_implementation','{"validation_fixture":true}'::jsonb),
('55555555-5555-4555-8555-555555555511'::uuid,'55555555-5555-4555-8555-555555555501'::uuid,'in_implementation','{"validation_fixture":true}'::jsonb),
('66666666-6666-4666-8666-666666666611'::uuid,'66666666-6666-4666-8666-666666666601'::uuid,'in_implementation','{"validation_fixture":true}'::jsonb),
('77777777-7777-4777-8777-777777777711'::uuid,'77777777-7777-4777-8777-777777777701'::uuid,'in_implementation','{"validation_fixture":true}'::jsonb);

-- Main case: assigned practitioner + verified sponsor Principal One.
insert into atlas.implementation_case_participants(
  id,implementation_case_id,human_user_id,relationship_kind,active,verified_at,basis,metadata
) values
(
 '44444444-4444-4444-8444-444444444421'::uuid,
 '44444444-4444-4444-8444-444444444411'::uuid,
 '33333333-3333-4333-8333-333333333331'::uuid,
 'practitioner',true,null,'{"basis":"validation_fixture"}'::jsonb,'{}'::jsonb
),
(
 '44444444-4444-4444-8444-444444444422'::uuid,
 '44444444-4444-4444-8444-444444444411'::uuid,
 '11111111-1111-4111-8111-111111111111'::uuid,
 'setup_sponsor',true,now(),'{"basis":"validation_fixture"}'::jsonb,'{}'::jsonb
);

-- Case two supplies an entitlement belonging to a different case.
insert into atlas.implementation_case_participants(
  id,implementation_case_id,human_user_id,relationship_kind,active,verified_at,basis,metadata
) values
(
 '55555555-5555-4555-8555-555555555521'::uuid,
 '55555555-5555-4555-8555-555555555511'::uuid,
 '33333333-3333-4333-8333-333333333331'::uuid,
 'practitioner',true,null,'{"basis":"validation_fixture"}'::jsonb,'{}'::jsonb
),
(
 '55555555-5555-4555-8555-555555555522'::uuid,
 '55555555-5555-4555-8555-555555555511'::uuid,
 '11111111-1111-4111-8111-111111111111'::uuid,
 'setup_sponsor',true,now(),'{"basis":"validation_fixture"}'::jsonb,'{}'::jsonb
);

-- Case three: practitioner assigned, deliberately no setup sponsor.
insert into atlas.implementation_case_participants(
  id,implementation_case_id,human_user_id,relationship_kind,active,verified_at,basis,metadata
) values (
 '66666666-6666-4666-8666-666666666621'::uuid,
 '66666666-6666-4666-8666-666666666611'::uuid,
 '33333333-3333-4333-8333-333333333331'::uuid,
 'practitioner',true,null,'{"basis":"validation_fixture"}'::jsonb,'{}'::jsonb
);

-- Case four: verified sponsor, deliberately no practitioner assignment.
insert into atlas.implementation_case_participants(
  id,implementation_case_id,human_user_id,relationship_kind,active,verified_at,basis,metadata
) values (
 '77777777-7777-4777-8777-777777777722'::uuid,
 '77777777-7777-4777-8777-777777777711'::uuid,
 '11111111-1111-4111-8111-111111111111'::uuid,
 'setup_sponsor',true,now(),'{"basis":"validation_fixture"}'::jsonb,'{}'::jsonb
);

insert into atlas.implementation_establishment_items(
  id,implementation_case_id,category,title,detail,status,author_user_id,basis
) values
('44444444-4444-4444-8444-444444444431'::uuid,'44444444-4444-4444-8444-444444444411'::uuid,'institution','Institution','','established','33333333-3333-4333-8333-333333333331'::uuid,'{}'::jsonb),
('44444444-4444-4444-8444-444444444432'::uuid,'44444444-4444-4444-8444-444444444411'::uuid,'ledger_scope','Ledger Scope','','established','33333333-3333-4333-8333-333333333331'::uuid,'{}'::jsonb),
('55555555-5555-4555-8555-555555555531'::uuid,'55555555-5555-4555-8555-555555555511'::uuid,'institution','Institution','','established','33333333-3333-4333-8333-333333333331'::uuid,'{}'::jsonb),
('55555555-5555-4555-8555-555555555532'::uuid,'55555555-5555-4555-8555-555555555511'::uuid,'ledger_scope','Ledger Scope','','established','33333333-3333-4333-8333-333333333331'::uuid,'{}'::jsonb),
('66666666-6666-4666-8666-666666666631'::uuid,'66666666-6666-4666-8666-666666666611'::uuid,'institution','Institution','','established','33333333-3333-4333-8333-333333333331'::uuid,'{}'::jsonb),
('66666666-6666-4666-8666-666666666632'::uuid,'66666666-6666-4666-8666-666666666611'::uuid,'ledger_scope','Ledger Scope','','established','33333333-3333-4333-8333-333333333331'::uuid,'{}'::jsonb),
('77777777-7777-4777-8777-777777777731'::uuid,'77777777-7777-4777-8777-777777777711'::uuid,'institution','Institution','','established','33333333-3333-4333-8333-333333333331'::uuid,'{}'::jsonb),
('77777777-7777-4777-8777-777777777732'::uuid,'77777777-7777-4777-8777-777777777711'::uuid,'ledger_scope','Ledger Scope','','established','33333333-3333-4333-8333-333333333331'::uuid,'{}'::jsonb);

insert into atlas.ledger_entitlements(
  id,implementation_case_id,source_purchase_id,entitlement_number,entitlement_kind,price_class,state,
  setup_price_cents,monthly_price_cents,commercial_basis,metadata
) values
('44444444-4444-4444-8444-444444444441'::uuid,'44444444-4444-4444-8444-444444444411'::uuid,'44444444-4444-4444-8444-444444444401'::uuid,1,'atlas_ledger','baseline_first','available',300000,40000,'{}'::jsonb,'{}'::jsonb),
('55555555-5555-4555-8555-555555555541'::uuid,'55555555-5555-4555-8555-555555555511'::uuid,'55555555-5555-4555-8555-555555555501'::uuid,1,'atlas_ledger','baseline_first','available',300000,40000,'{}'::jsonb,'{}'::jsonb),
('66666666-6666-4666-8666-666666666641'::uuid,'66666666-6666-4666-8666-666666666611'::uuid,'66666666-6666-4666-8666-666666666601'::uuid,1,'atlas_ledger','baseline_first','available',300000,40000,'{}'::jsonb,'{}'::jsonb),
('77777777-7777-4777-8777-777777777741'::uuid,'77777777-7777-4777-8777-777777777711'::uuid,'77777777-7777-4777-8777-777777777701'::uuid,1,'atlas_ledger','baseline_first','available',300000,40000,'{}'::jsonb,'{}'::jsonb);
