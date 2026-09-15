-- Commercial Financial Reality v1 postconditions.
-- Runs only on the disposable production-schema clone.

do $commercial_financial_postconditions$
declare
  v_position record;
  v_order_id uuid;
  v_payment_id uuid;
  v_count integer;
  v_definition text;
begin
  -- Archived/test source truth remains outside canonical Financial Reality.
  if exists(
    select 1
    from atlas.flower_commercial_order_extensions x
    where x.flower_sale_order_id='95224342-0000-4000-8000-000000000081'::uuid
  ) then
    raise exception 'Archived test Flower Sale acquired a canonical Commercial Order.';
  end if;

  -- Historical production-shaped Flower commerce remains collection_unknown;
  -- no receivable balance is fabricated from absence of payment evidence.
  select * into v_position
  from atlas.commercial_financial_position_v1 p
  where p.source_domain='flower'
    and p.source_kind='flower_sale_order'
    and p.source_id='95224342-0000-4000-8000-000000000080';

  if v_position.commercial_order_id is null
     or v_position.effective_organization_id is distinct from '95224342-0000-4000-8000-000000000011'::uuid
     or v_position.effective_ledger_id is distinct from '95224342-0000-4000-8000-000000000050'::uuid
     or v_position.committed_amount<>25.00
     or v_position.financial_state<>'collection_unknown'
     or v_position.open_amount is not null
     or v_position.financial_coverage then
    raise exception 'Historical Flower Financial Reality is incorrect: %',row_to_json(v_position);
  end if;

  -- Existing Registration evidence must reconcile into universal payment truth
  -- without inventing Connected Source custody.
  select * into v_position
  from atlas.commercial_financial_position_v1 p
  where p.source_domain='community_registration'
    and p.source_kind='registration'
    and p.source_id='95224342-0000-4000-8000-000000000092';

  if v_position.commercial_order_id is null
     or v_position.effective_ledger_id is distinct from '95224342-0000-4000-8000-000000000050'::uuid
     or v_position.committed_amount<>60.00
     or v_position.gross_collected_amount<>60.00
     or v_position.returned_amount<>0
     or v_position.net_collected_amount<>60.00
     or v_position.open_amount<>0
     or v_position.financial_state<>'paid'
     or not v_position.financial_coverage then
    raise exception 'Paid Registration did not reconcile correctly: %',row_to_json(v_position);
  end if;

  select x.commercial_payment_id into v_payment_id
  from atlas.community_registration_commercial_payment_extensions x
  where x.registration_payment_id='95224342-0000-4000-8000-000000000093'::uuid;

  if v_payment_id is null then
    raise exception 'Registration Commercial Payment extension missing.';
  end if;

  select count(*) into v_count
  from atlas.commercial_payment_events e
  where e.commercial_payment_id=v_payment_id
    and e.event_kind='succeeded'
    and e.amount_delta=60.00;
  if v_count<>1 then
    raise exception 'Expected one succeeded Registration payment event; found %.',v_count;
  end if;

  -- Internal reconciliation replay is idempotent.
  perform atlas.ensure_registration_commercial_payment_v1(
    '95224342-0000-4000-8000-000000000093'::uuid
  );
  perform atlas.ensure_registration_commercial_payment_v1(
    '95224342-0000-4000-8000-000000000093'::uuid
  );

  select count(*) into v_count
  from atlas.commercial_payment_events e
  where e.commercial_payment_id=v_payment_id
    and e.event_kind='succeeded'
    and e.amount_delta=60.00;
  if v_count<>1 then
    raise exception 'Registration payment replay duplicated succeeded evidence.';
  end if;

  -- A Sale born after Package 5 installation must synchronize through the
  -- current Flower domain writer consequence and derive an open position.
  insert into atlas.flower_sale_orders(
    id,farm_id,buyer_relationship_id,customer_label,sales_channel,event_key,sale_date,
    fulfillment_mode,fulfillment_due_date,fulfillment_due_time,fulfillment_membership_id,
    subtotal_amount,tax_amount,tip_amount,total_amount,currency,source_task_id,note,
    idempotency_key,recorded_by_membership_id,created_by_user_id,metadata
  ) values (
    '95224342-0000-4000-8000-000000000083'::uuid,
    '95224342-0000-4000-8000-000000000030'::uuid,
    null,'Post-cutover Fixture Florist','wholesale',null,'2026-09-16',
    'immediate_handoff',null,null,null,
    40.00,0,0,40.00,'USD',null,'Post-cutover governed Financial Reality proof.',
    'commercial-financial-fixture-post-cutover-sale',
    '95224342-0000-4000-8000-000000000040'::uuid,
    '95224342-0000-4000-8000-000000000001'::uuid,
    '{"validation_fixture":true}'::jsonb
  );

  select x.commercial_order_id into v_order_id
  from atlas.flower_commercial_order_extensions x
  where x.flower_sale_order_id='95224342-0000-4000-8000-000000000083'::uuid;

  if v_order_id is null then
    raise exception 'Post-cutover Flower Sale did not synchronize to Commercial Order.';
  end if;

  select * into v_position
  from atlas.commercial_financial_position_v1 p
  where p.commercial_order_id=v_order_id;

  if v_position.effective_organization_id is distinct from '95224342-0000-4000-8000-000000000011'::uuid
     or v_position.effective_ledger_id is distinct from '95224342-0000-4000-8000-000000000050'::uuid
     or v_position.committed_amount<>40.00
     or v_position.net_collected_amount<>0
     or v_position.open_amount<>40.00
     or v_position.financial_state<>'open'
     or not v_position.financial_coverage
     or v_position.financial_coverage_basis<>'governed_from_order_birth' then
    raise exception 'Post-cutover Flower Financial Reality is incorrect: %',row_to_json(v_position);
  end if;

  -- Domain cancellation changes the financial consequence; it does not invent
  -- a refund or erase the underlying Sale.
  insert into atlas.flower_sale_order_cancellation_events(
    id,farm_id,sale_order_id,reason_kind,note,recorded_by_membership_id,
    idempotency_key,created_by_user_id,metadata
  ) values (
    '95224342-0000-4000-8000-000000000084'::uuid,
    '95224342-0000-4000-8000-000000000030'::uuid,
    '95224342-0000-4000-8000-000000000083'::uuid,
    'customer_cancelled','Validation cancellation.',
    '95224342-0000-4000-8000-000000000040'::uuid,
    'commercial-financial-fixture-post-cutover-cancel',
    '95224342-0000-4000-8000-000000000001'::uuid,
    '{"validation_fixture":true}'::jsonb
  );

  select * into v_position
  from atlas.commercial_financial_position_v1 p
  where p.commercial_order_id=v_order_id;

  if v_position.financial_state<>'cancelled'
     or v_position.open_amount<>0
     or v_position.net_collected_amount<>0 then
    raise exception 'Flower cancellation Financial Reality is incorrect: %',row_to_json(v_position);
  end if;

  -- Current Package 4 Flower v2 remains the availability/concurrency writer.
  select pg_get_functiondef(p.oid) into v_definition
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='atlas' and p.proname='record_flower_sale_core_v2'
  limit 1;

  if v_definition is null
     or position('cancellation_and_disposition_aware_v1' in v_definition)=0 then
    raise exception 'Package 4 Flower Sale v2 was replaced or lost.';
  end if;

  -- Browser access is through the Ledger-authorized function, not direct view/table access.
  if has_table_privilege('authenticated','atlas.commercial_financial_position_v1','SELECT')
     or has_table_privilege('anon','atlas.commercial_financial_position_v1','SELECT') then
    raise exception 'Direct browser privilege leaked onto Commercial Financial Reality view.';
  end if;

  if not has_function_privilege(
       'authenticated','atlas.commercial_financial_position_self_api_v1(uuid)','EXECUTE'
     )
     or has_function_privilege(
       'anon','atlas.commercial_financial_position_self_api_v1(uuid)','EXECUTE'
     ) then
    raise exception 'Commercial Financial Reality API privilege boundary is incorrect.';
  end if;

  if has_function_privilege(
       'authenticated','atlas.ensure_flower_sale_commercial_order_v1(uuid)','EXECUTE'
     )
     or has_function_privilege(
       'service_role','atlas.ensure_flower_sale_commercial_order_v1(uuid)','EXECUTE'
     )
     or has_function_privilege(
       'authenticated','atlas.ensure_registration_commercial_payment_v1(uuid)','EXECUTE'
     )
     or has_function_privilege(
       'service_role','atlas.ensure_registration_commercial_payment_v1(uuid)','EXECUTE'
     ) then
    raise exception 'Internal commercial synchronization function leaked executable privilege.';
  end if;

  if not exists(
    select 1
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas' and c.relname='flower_sale_orders'
      and t.tgname='p20_flower_sale_universal_commerce_sync_v1'
      and not t.tgisinternal
  ) or not exists(
    select 1
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas' and c.relname='community_registrations'
      and t.tgname='p20_registration_universal_commerce_sync_v1'
      and not t.tgisinternal
  ) or not exists(
    select 1
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas' and c.relname='community_registration_payments'
      and t.tgname='p20_registration_payment_universal_commerce_sync_v1'
      and not t.tgisinternal
  ) then
    raise exception 'One or more forward commercial synchronization triggers are missing.';
  end if;
end;
$commercial_financial_postconditions$;

-- Prove the authenticated Ledger-authorized read with the fixture owner.
begin;
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '95224342-0000-4000-8000-000000000001',
  true
);

do $authenticated_read$
declare
  v_result jsonb;
begin
  v_result:=atlas.commercial_financial_position_self_api_v1(
    '95224342-0000-4000-8000-000000000050'::uuid
  );

  if v_result is null
     or v_result->>'ledgerId'<>'95224342-0000-4000-8000-000000000050'
     or jsonb_array_length(v_result->'orders')<2 then
    raise exception 'Authenticated Ledger Financial Reality read failed: %',v_result;
  end if;
end;
$authenticated_read$;
rollback;
