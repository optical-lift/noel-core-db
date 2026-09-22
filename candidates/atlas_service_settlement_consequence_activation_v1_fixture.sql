insert into auth.users(id,email,created_at,updated_at)
values
(
  'a6c10000-0000-4000-8000-000000000001'::uuid,
  'atlas-human@example.invalid',
  now(),now()
);

insert into atlas.atlas_service_commercial_compositions(
  id,auth_user_id,status,currency,metadata
) values
(
  'a6c10000-0000-4000-8000-000000000010'::uuid,
  'a6c10000-0000-4000-8000-000000000001'::uuid,
  'open','USD',
  '{"validationFixture":"personal_forward_activation"}'::jsonb
),
(
  'a6c10000-0000-4000-8000-000000000020'::uuid,
  'a6c10000-0000-4000-8000-000000000001'::uuid,
  'open','USD',
  '{"validationFixture":"ledger_forward_activation"}'::jsonb
);

insert into atlas.atlas_service_payer_profiles(
  id,composition_id,payer_kind,display_label,billing_email,
  provider,provider_customer_id,status,metadata
) values
(
  'a6c10000-0000-4000-8000-000000000011'::uuid,
  'a6c10000-0000-4000-8000-000000000010'::uuid,
  'institution','Example Employer','billing-personal@example.invalid',
  'stripe','cus_forward_personal','active',
  '{"validationFixture":true}'::jsonb
),
(
  'a6c10000-0000-4000-8000-000000000021'::uuid,
  'a6c10000-0000-4000-8000-000000000020'::uuid,
  'institution','Example Institution','treasurer@example.invalid',
  'stripe','cus_forward_ledger','active',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.atlas_service_activation_groups(
  id,composition_id,activation_key,activation_kind,state,metadata
) values
(
  'a6c10000-0000-4000-8000-000000000012'::uuid,
  'a6c10000-0000-4000-8000-000000000010'::uuid,
  'personal-base-proof','personal_atlas','open',
  '{"validationFixture":true}'::jsonb
),
(
  'a6c10000-0000-4000-8000-000000000022'::uuid,
  'a6c10000-0000-4000-8000-000000000020'::uuid,
  'first-ledger-proof','ledger_implementation_first_family','open',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.atlas_service_commercial_composition_items(
  id,composition_id,item_key,item_kind,charge_kind,state,currency,
  unit_amount_cents,quantity,billing_interval,requires_explicit_election,
  elected_at,election_evidence,activation_group_id,metadata
) values
(
  'a6c10000-0000-4000-8000-000000000013'::uuid,
  'a6c10000-0000-4000-8000-000000000010'::uuid,
  'personal-setup','atlas_initial_setup','one_time','settlement_ready','USD',
  3995,1,null,false,
  '2026-09-22T16:00:00Z'::timestamptz,
  '{"basis":"entry_consent"}'::jsonb,
  'a6c10000-0000-4000-8000-000000000012'::uuid,
  '{"validationFixture":true}'::jsonb
),
(
  'a6c10000-0000-4000-8000-000000000014'::uuid,
  'a6c10000-0000-4000-8000-000000000010'::uuid,
  'personal-base','atlas_base_recurring','recurring','settlement_ready','USD',
  700,1,'month',false,
  '2026-09-22T16:00:00Z'::timestamptz,
  '{"basis":"entry_consent"}'::jsonb,
  'a6c10000-0000-4000-8000-000000000012'::uuid,
  '{"validationFixture":true}'::jsonb
),
(
  'a6c10000-0000-4000-8000-000000000023'::uuid,
  'a6c10000-0000-4000-8000-000000000020'::uuid,
  'ledger-setup','ledger_implementation_first_family','one_time','settlement_ready','USD',
  300000,1,null,true,
  '2026-09-22T16:05:00Z'::timestamptz,
  '{"basis":"explicit_ledger_review","approved":true}'::jsonb,
  'a6c10000-0000-4000-8000-000000000022'::uuid,
  '{"validationFixture":true}'::jsonb
),
(
  'a6c10000-0000-4000-8000-000000000024'::uuid,
  'a6c10000-0000-4000-8000-000000000020'::uuid,
  'ledger-recurring','ledger_recurring','recurring','settlement_ready','USD',
  40000,1,'month',true,
  '2026-09-22T16:05:00Z'::timestamptz,
  '{"basis":"explicit_ledger_review","approved":true}'::jsonb,
  'a6c10000-0000-4000-8000-000000000022'::uuid,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.atlas_service_item_payer_responsibilities(
  composition_item_id,payer_profile_id,state,
  acceptance_evidence,accepted_at,metadata
) values
(
  'a6c10000-0000-4000-8000-000000000013'::uuid,
  'a6c10000-0000-4000-8000-000000000011'::uuid,
  'accepted','{"basis":"fixture"}'::jsonb,now(),'{}'::jsonb
),
(
  'a6c10000-0000-4000-8000-000000000014'::uuid,
  'a6c10000-0000-4000-8000-000000000011'::uuid,
  'accepted','{"basis":"fixture"}'::jsonb,now(),'{}'::jsonb
),
(
  'a6c10000-0000-4000-8000-000000000023'::uuid,
  'a6c10000-0000-4000-8000-000000000021'::uuid,
  'accepted','{"basis":"fixture"}'::jsonb,now(),'{}'::jsonb
),
(
  'a6c10000-0000-4000-8000-000000000024'::uuid,
  'a6c10000-0000-4000-8000-000000000021'::uuid,
  'accepted','{"basis":"fixture"}'::jsonb,now(),'{}'::jsonb
);
