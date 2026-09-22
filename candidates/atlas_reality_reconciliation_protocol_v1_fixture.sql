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


-- Continuation qualification domain 3: one source dependency is satisfied while
-- two independent dependencies still block the same downstream readiness target.
insert into atlas.farms(
  id,stable_key,name,status,organization_id,metadata
) values (
  'f4900000-0000-4000-8000-000000000001'::uuid,
  'reality_continuation_fixture_farm',
  'Reality Continuation Fixture Farm',
  'active',
  'f4800000-0000-4000-8000-000000000010'::uuid,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.growing_objects(
  id,farm_id,stable_key,label,object_type,metadata
) values
(
  'f4900000-0000-4000-8000-000000000011'::uuid,
  'f4900000-0000-4000-8000-000000000001'::uuid,
  'continuation-bed-a','Continuation Bed A','bed',
  '{"validationFixture":true}'::jsonb
),
(
  'f4900000-0000-4000-8000-000000000012'::uuid,
  'f4900000-0000-4000-8000-000000000001'::uuid,
  'continuation-bed-b','Continuation Bed B','bed',
  '{"validationFixture":true}'::jsonb
),
(
  'f4900000-0000-4000-8000-000000000013'::uuid,
  'f4900000-0000-4000-8000-000000000001'::uuid,
  'continuation-bed-c','Continuation Bed C','bed',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.maintenance_objects(
  id,farm_id,object_id,maintenance_type,condition,
  reset_effort_minutes,maintenance_effort_minutes,current_effort_minutes,
  remaining_effort_minutes,normal_return_interval_days,last_completed_at,
  condition_reported_at,source,estimate_source,metadata
) values
(
  'f4900000-0000-4000-8000-000000000021'::uuid,
  'f4900000-0000-4000-8000-000000000001'::uuid,
  'f4900000-0000-4000-8000-000000000011'::uuid,
  'weed','maintained',60,20,0,0,21,
  '2026-09-22 16:00:00+00','2026-09-22 16:00:00+00',
  'validation_fixture','validation_fixture',
  '{"validationFixture":true}'::jsonb
),
(
  'f4900000-0000-4000-8000-000000000022'::uuid,
  'f4900000-0000-4000-8000-000000000001'::uuid,
  'f4900000-0000-4000-8000-000000000012'::uuid,
  'weed','moderate',60,20,20,20,21,
  null,'2026-09-22 16:00:00+00',
  'validation_fixture','validation_fixture',
  '{"validationFixture":true}'::jsonb
),
(
  'f4900000-0000-4000-8000-000000000023'::uuid,
  'f4900000-0000-4000-8000-000000000001'::uuid,
  'f4900000-0000-4000-8000-000000000013'::uuid,
  'weed','heavy',60,20,40,40,21,
  null,'2026-09-22 16:00:00+00',
  'validation_fixture','validation_fixture',
  '{"validationFixture":true}'::jsonb
);

-- Schema-only production clones do not include operation-class reference data.
-- Seed the exact canonical class that the real task classifier assigns to this
-- synthetic planting Task. This preserves both the classifier and FK law.
insert into atlas.operation_classes(
  stable_key,label,operation_domain,definition,active,metadata
) values (
  'establish_aboveground',
  'Establish aboveground',
  'cultivation',
  'Establish a crop or plant whose working target is primarily aboveground growth, including sowing, potting up, set-out, and ordinary transplanting.',
  true,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.tasks(
  id,title,task_type,status,due_date,metadata,action_key,
  organization_id,task_scope,visibility_scope,origin_kind,
  work_lane,commitment_kind
) values (
  'f4900000-0000-4000-8000-000000000031'::uuid,
  'Continuation planting readiness target',
  'planting',
  'blocked',
  '2026-09-23',
  '{"bed_readiness_required":true,"validationFixture":true}'::jsonb,
  'plant',
  'f4800000-0000-4000-8000-000000000010'::uuid,
  'project',
  'system_internal',
  'generated',
  'required',
  'dependency'
);

insert into atlas.maintenance_dependencies(
  id,farm_id,maintenance_object_id,dependent_task_id,
  dependency_type,active,satisfied_at,metadata
) values
(
  'f4900000-0000-4000-8000-000000000041'::uuid,
  'f4900000-0000-4000-8000-000000000001'::uuid,
  'f4900000-0000-4000-8000-000000000021'::uuid,
  'f4900000-0000-4000-8000-000000000031'::uuid,
  'blocks_task',true,'2026-09-22 16:00:00+00',
  '{"source":"automatic_bed_readiness","ready_by_date":"2026-09-23","validationFixture":true}'::jsonb
),
(
  'f4900000-0000-4000-8000-000000000042'::uuid,
  'f4900000-0000-4000-8000-000000000001'::uuid,
  'f4900000-0000-4000-8000-000000000022'::uuid,
  'f4900000-0000-4000-8000-000000000031'::uuid,
  'blocks_task',true,null,
  '{"source":"automatic_bed_readiness","ready_by_date":"2026-09-23","validationFixture":true}'::jsonb
),
(
  'f4900000-0000-4000-8000-000000000043'::uuid,
  'f4900000-0000-4000-8000-000000000001'::uuid,
  'f4900000-0000-4000-8000-000000000023'::uuid,
  'f4900000-0000-4000-8000-000000000031'::uuid,
  'blocks_task',true,null,
  '{"source":"automatic_bed_readiness","ready_by_date":"2026-09-23","validationFixture":true}'::jsonb
);


-- Reconciliation qualification: deliberately stale the downstream Task gate
-- without changing native dependency truth. This creates a lawful automatic
-- reconciliation case for the bounded Bed Readiness adapter.
update atlas.tasks
set status='open',
    blocker_text=null,
    metadata=(
      coalesce(metadata,'{}'::jsonb)
      - 'bed_readiness_gate_restore'
      - 'bed_readiness_gate_waiting_text'
      - 'execution_locked'
      - 'execution_lock_kind'
      - 'bed_readiness_blocking_beds'
      - 'bed_readiness_blocking_bed_count'
      - 'bed_readiness_due_now'
    ) || jsonb_build_object(
      'bed_readiness_gate_state','stale_fixture',
      'validationReconciliationStaleGate',true
    ),
    updated_at='2026-09-22 16:10:00+00'
where id='f4900000-0000-4000-8000-000000000031'::uuid;
