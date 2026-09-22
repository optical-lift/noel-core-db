-- Clone-only fixture for Atlas Reality Transition Receipt v1.
-- Creates structurally different Company Work and Commercial/Financial
-- transition specimens without introducing any generic transition storage.

insert into atlas.organizations(
  id,stable_key,name,status,metadata,onboarding_state
) values (
  'f4800000-0000-4000-8000-000000000010'::uuid,
  'reality_transition_receipt_fixture_org',
  'Reality Transition Receipt Fixture Organization',
  'active',
  '{"validationFixture":true}'::jsonb,
  'ready'
);

insert into atlas.ledgers(
  id,stable_key,organization_id,ledger_kind,status,metadata,name
) values (
  'f4800000-0000-4000-8000-000000000020'::uuid,
  'reality_transition_receipt_fixture_ledger',
  'f4800000-0000-4000-8000-000000000010'::uuid,
  'organization_governing',
  'active',
  '{"validationFixture":true}'::jsonb,
  'Reality Transition Receipt Fixture Ledger'
);

-- The real Organization Ledger projection resolves through the Organization's
-- active compatibility-primary Ledger participation. A bare Ledger row is not
-- sufficient authority for institutional consequence projection.
insert into atlas.ledger_organization_participations(
  id,ledger_id,organization_id,participation_kind,is_compatibility_primary,
  status,basis,metadata
) values (
  'f4800000-0000-4000-8000-000000000021'::uuid,
  'f4800000-0000-4000-8000-000000000020'::uuid,
  'f4800000-0000-4000-8000-000000000010'::uuid,
  'governing',
  true,
  'active',
  '{"kind":"validation_fixture","reason":"exercise real Organization Ledger compatibility law"}'::jsonb,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.work_result_contract_policies(
  contract_key,source_domain,acceptance_mode,active,description,metadata
) values (
  'reality_transition_receipt_manager_acceptance_v1',
  'organization',
  'manager_acceptance',
  true,
  'Validation-only manager acceptance contract for Reality Transition Receipt qualification.',
  '{"validationFixture":true}'::jsonb
);

-- Company Work specimen A: reported -> accepted -> completed -> Ledger consequence.
insert into atlas.work_items(
  id,organization_id,title,work_state,result_contract_key,completed_at,metadata
) values (
  'f4800000-0000-4000-8000-000000000101'::uuid,
  'f4800000-0000-4000-8000-000000000010'::uuid,
  'Effective Company Work transition',
  'open',
  'reality_transition_receipt_manager_acceptance_v1',
  null,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.work_execution_results(
  id,organization_id,work_item_id,result_kind,result_contract_key,
  idempotency_key,payload,reported_at,metadata
) values (
  'f4800000-0000-4000-8000-000000000111'::uuid,
  'f4800000-0000-4000-8000-000000000010'::uuid,
  'f4800000-0000-4000-8000-000000000101'::uuid,
  'completed',
  'reality_transition_receipt_manager_acceptance_v1',
  'receipt-fixture-effective-result',
  '{"validationFixture":true}'::jsonb,
  '2026-09-22 11:55:00+00',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.work_result_acceptances(
  id,organization_id,work_item_id,execution_result_id,decision,
  acceptance_kind,accepted_by_domain,accepted_at,evidence,metadata
) values (
  'f4800000-0000-4000-8000-000000000121'::uuid,
  'f4800000-0000-4000-8000-000000000010'::uuid,
  'f4800000-0000-4000-8000-000000000101'::uuid,
  'f4800000-0000-4000-8000-000000000111'::uuid,
  'accepted',
  'management_authority',
  'organization',
  '2026-09-22 12:00:00+00',
  '{"validationFixture":true}'::jsonb,
  '{"validationFixture":true}'::jsonb
);

-- Exercise the real completion guard/projection. The existing Company Work
-- runtime must create the Organization Ledger consequence from accepted result
-- evidence; the fixture does not manufacture it directly.
update atlas.work_items
set work_state='completed',
    completed_at='2026-09-22 12:00:00+00',
    updated_at='2026-09-22 12:00:00+00'
where id='f4800000-0000-4000-8000-000000000101'::uuid;

-- Company Work specimen B: reported result, no adjudication yet.
insert into atlas.work_items(
  id,organization_id,title,work_state,result_contract_key,metadata
) values (
  'f4800000-0000-4000-8000-000000000102'::uuid,
  'f4800000-0000-4000-8000-000000000010'::uuid,
  'Unresolved Company Work transition',
  'open',
  'reality_transition_receipt_manager_acceptance_v1',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.work_execution_results(
  id,organization_id,work_item_id,result_kind,result_contract_key,
  idempotency_key,payload,reported_at,metadata
) values (
  'f4800000-0000-4000-8000-000000000112'::uuid,
  'f4800000-0000-4000-8000-000000000010'::uuid,
  'f4800000-0000-4000-8000-000000000102'::uuid,
  'completed',
  'reality_transition_receipt_manager_acceptance_v1',
  'receipt-fixture-unresolved-result',
  '{"validationFixture":true}'::jsonb,
  '2026-09-22 12:10:00+00',
  '{"validationFixture":true}'::jsonb
);

-- Company Work specimen C: explicit rejected result.
insert into atlas.work_items(
  id,organization_id,title,work_state,result_contract_key,metadata
) values (
  'f4800000-0000-4000-8000-000000000103'::uuid,
  'f4800000-0000-4000-8000-000000000010'::uuid,
  'Rejected Company Work transition',
  'open',
  'reality_transition_receipt_manager_acceptance_v1',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.work_execution_results(
  id,organization_id,work_item_id,result_kind,result_contract_key,
  idempotency_key,payload,reported_at,metadata
) values (
  'f4800000-0000-4000-8000-000000000113'::uuid,
  'f4800000-0000-4000-8000-000000000010'::uuid,
  'f4800000-0000-4000-8000-000000000103'::uuid,
  'completed',
  'reality_transition_receipt_manager_acceptance_v1',
  'receipt-fixture-rejected-result',
  '{"validationFixture":true}'::jsonb,
  '2026-09-22 12:20:00+00',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.work_result_acceptances(
  id,organization_id,work_item_id,execution_result_id,decision,
  acceptance_kind,accepted_by_domain,accepted_at,evidence,metadata
) values (
  'f4800000-0000-4000-8000-000000000123'::uuid,
  'f4800000-0000-4000-8000-000000000010'::uuid,
  'f4800000-0000-4000-8000-000000000103'::uuid,
  'f4800000-0000-4000-8000-000000000113'::uuid,
  'rejected',
  'management_authority',
  'organization',
  '2026-09-22 12:25:00+00',
  '{"validationFixture":true}'::jsonb,
  '{"validationFixture":true}'::jsonb
);

-- Commercial specimen A: governed order birth + successful payment + independent
-- fulfillment. Financial receipt must be paid and must not use fulfillment as
-- financial basis.
insert into atlas.commercial_orders(
  id,organization_id,order_kind,order_date,channel,subtotal_amount,
  tax_amount,tip_amount,total_amount,currency,idempotency_key,metadata,created_at
) values (
  'f4800000-0000-4000-8000-000000000201'::uuid,
  'f4800000-0000-4000-8000-000000000010'::uuid,
  'sale','2026-09-22','validation',
  100.00,0,0,100.00,'USD',
  'receipt-fixture-paid-order',
  '{"sourceDomain":"validation_commercial","financialRealityCoverage":"governed_from_order_birth","validationFixture":true}'::jsonb,
  '2026-09-22 13:00:00+00'
);

insert into atlas.commercial_order_events(
  id,commercial_order_id,event_kind,occurred_at,idempotency_key,metadata
) values (
  'f4800000-0000-4000-8000-000000000211'::uuid,
  'f4800000-0000-4000-8000-000000000201'::uuid,
  'recorded','2026-09-22 13:00:00+00',
  'receipt-fixture-paid-order-recorded',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.commercial_payments(
  id,organization_id,commercial_order_id,provider_key,provider_payment_key,
  amount,currency,observed_state,paid_at,metadata,created_at
) values (
  'f4800000-0000-4000-8000-000000000221'::uuid,
  'f4800000-0000-4000-8000-000000000010'::uuid,
  'f4800000-0000-4000-8000-000000000201'::uuid,
  'fixture','receipt-fixture-payment-1',
  100.00,'USD','succeeded','2026-09-22 13:05:00+00',
  '{"validationFixture":true}'::jsonb,
  '2026-09-22 13:05:00+00'
);

insert into atlas.commercial_payment_events(
  id,commercial_payment_id,event_kind,amount_delta,currency,occurred_at,
  provider_event_key,metadata
) values (
  'f4800000-0000-4000-8000-000000000231'::uuid,
  'f4800000-0000-4000-8000-000000000221'::uuid,
  'succeeded',100.00,'USD','2026-09-22 13:05:00+00',
  'receipt-fixture-payment-event-1',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.commercial_fulfillment_events(
  id,organization_id,commercial_order_id,event_kind,fulfillment_method,
  occurred_at,effective_date,idempotency_key,metadata
) values (
  'f4800000-0000-4000-8000-000000000241'::uuid,
  'f4800000-0000-4000-8000-000000000010'::uuid,
  'f4800000-0000-4000-8000-000000000201'::uuid,
  'fulfilled','validation',
  '2026-09-22 14:00:00+00','2026-09-22',
  'receipt-fixture-fulfillment-1',
  '{"validationFixture":true}'::jsonb
);

-- Commercial specimen B: fulfilled but financially open.
insert into atlas.commercial_orders(
  id,organization_id,order_kind,order_date,channel,subtotal_amount,
  tax_amount,tip_amount,total_amount,currency,idempotency_key,metadata,created_at
) values (
  'f4800000-0000-4000-8000-000000000202'::uuid,
  'f4800000-0000-4000-8000-000000000010'::uuid,
  'sale','2026-09-22','validation',
  50.00,0,0,50.00,'USD',
  'receipt-fixture-open-order',
  '{"sourceDomain":"validation_commercial","financialRealityCoverage":"governed_from_order_birth","validationFixture":true}'::jsonb,
  '2026-09-22 15:00:00+00'
);

insert into atlas.commercial_order_events(
  id,commercial_order_id,event_kind,occurred_at,idempotency_key,metadata
) values (
  'f4800000-0000-4000-8000-000000000212'::uuid,
  'f4800000-0000-4000-8000-000000000202'::uuid,
  'recorded','2026-09-22 15:00:00+00',
  'receipt-fixture-open-order-recorded',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.commercial_fulfillment_events(
  id,organization_id,commercial_order_id,event_kind,fulfillment_method,
  occurred_at,effective_date,idempotency_key,metadata
) values (
  'f4800000-0000-4000-8000-000000000242'::uuid,
  'f4800000-0000-4000-8000-000000000010'::uuid,
  'f4800000-0000-4000-8000-000000000202'::uuid,
  'fulfilled','validation',
  '2026-09-22 15:30:00+00','2026-09-22',
  'receipt-fixture-fulfillment-2',
  '{"validationFixture":true}'::jsonb
);

-- Commercial specimen C: historical order with no collection coverage.
insert into atlas.commercial_orders(
  id,organization_id,order_kind,order_date,channel,subtotal_amount,
  tax_amount,tip_amount,total_amount,currency,idempotency_key,metadata,created_at
) values (
  'f4800000-0000-4000-8000-000000000203'::uuid,
  'f4800000-0000-4000-8000-000000000010'::uuid,
  'sale','2026-09-20','validation',
  25.00,0,0,25.00,'USD',
  'receipt-fixture-unknown-order',
  '{"sourceDomain":"validation_commercial","validationFixture":true}'::jsonb,
  '2026-09-20 15:00:00+00'
);

insert into atlas.commercial_order_events(
  id,commercial_order_id,event_kind,occurred_at,idempotency_key,metadata
) values (
  'f4800000-0000-4000-8000-000000000213'::uuid,
  'f4800000-0000-4000-8000-000000000203'::uuid,
  'recorded','2026-09-20 15:00:00+00',
  'receipt-fixture-unknown-order-recorded',
  '{"validationFixture":true}'::jsonb
);
