-- Package 5 Money Collection current-main v1 postconditions.
-- Runs only against the disposable production-schema clone.

do $money_postconditions$
declare
  v_flower_obligation uuid;
  v_registration_obligation uuid;
  v_receipt uuid;
  v_allocation uuid;
  v_position record;
  v_retry uuid;
  v_count integer;
  v_definition text;
begin
  select count(*) into v_count from atlas.money_obligations;
  if v_count<>2 then
    raise exception 'Expected exactly 2 canonical Money obligations; found %.',v_count;
  end if;

  if exists(
    select 1 from atlas.money_obligations
    where source_domain='flower'
      and source_kind='flower_sale_order'
      and source_id='95154000-0000-4000-8000-000000000041'
  ) then
    raise exception 'Archived/test Flower Sale must not establish canonical Money.';
  end if;

  select id into v_flower_obligation
  from atlas.money_obligations
  where source_domain='flower'
    and source_kind='flower_sale_order'
    and source_id='95154000-0000-4000-8000-000000000040'
    and obligation_kind='sale_total';
  if v_flower_obligation is null then
    raise exception 'Canonical Flower Sale obligation missing.';
  end if;

  select * into v_position
  from atlas.money_obligation_position_v1
  where obligation_id=v_flower_obligation;
  if v_position.original_amount<>25.00 or v_position.open_amount<>25.00
     or v_position.effective_state<>'open' or v_position.currency<>'USD' then
    raise exception 'Flower Money position is incorrect: %',row_to_json(v_position);
  end if;

  select id into v_registration_obligation
  from atlas.money_obligations
  where source_domain='community_registration'
    and source_kind='registration'
    and source_id='95154000-0000-4000-8000-000000000052'
    and obligation_kind='participation_fee';
  if v_registration_obligation is null then
    raise exception 'Registration Money obligation missing.';
  end if;

  select * into v_position
  from atlas.money_obligation_position_v1
  where obligation_id=v_registration_obligation;
  if v_position.original_amount<>60.00 or v_position.open_amount<>0
     or v_position.net_applied_amount<>60.00 or v_position.effective_state<>'paid'
     or v_position.currency<>'USD' then
    raise exception 'Registration Money position did not reconcile paid evidence: %',row_to_json(v_position);
  end if;

  select r.id into v_receipt
  from atlas.money_receipts r
  where r.evidence_domain='community_registration'
    and r.evidence_kind='registration_payment'
    and r.evidence_id='95154000-0000-4000-8000-000000000053';
  if v_receipt is null then
    raise exception 'Registration receipt missing.';
  end if;

  select a.id into v_allocation
  from atlas.money_receipt_allocations a
  where a.receipt_id=v_receipt and a.obligation_id=v_registration_obligation;
  if v_allocation is null then
    raise exception 'Registration receipt allocation missing.';
  end if;

  -- Idempotent source replay must return the existing obligation.
  v_retry:=atlas.ensure_money_obligation_for_flower_sale_v1(
    '95154000-0000-4000-8000-000000000040'::uuid
  );
  if v_retry is distinct from v_flower_obligation then
    raise exception 'Flower source replay did not converge on existing obligation.';
  end if;

  -- Append-only Money truth cannot be rewritten in place.
  begin
    update atlas.money_obligations set metadata=metadata where id=v_flower_obligation;
    raise exception 'Money obligation update unexpectedly succeeded.';
  exception when sqlstate '55000' then
    null;
  end;

  -- A reversal preserves receipt history while reopening the obligation position.
  perform atlas.reverse_money_receipt_core_v1(
    v_receipt,
    v_allocation,
    10.00,
    'refund',
    'validation',
    'refund_evidence',
    'money-fixture-refund-001',
    '2026-09-15T13:00:00-05'::timestamptz,
    'money-fixture:refund-001',
    '{"validation_fixture":true}'::jsonb
  );

  select * into v_position
  from atlas.money_obligation_position_v1
  where obligation_id=v_registration_obligation;
  if v_position.net_applied_amount<>50.00 or v_position.open_amount<>10.00
     or v_position.effective_state<>'reopened' then
    raise exception 'Refund/reversal did not reopen Money position correctly: %',row_to_json(v_position);
  end if;

  -- Domain cancellation cannot erase a receipt-bearing obligation.
  begin
    perform atlas.void_money_obligation_core_v1(
      v_registration_obligation,
      'validation_cancel',
      'validation',
      'cancel_evidence',
      'money-fixture-cancel-001',
      null,
      'money-fixture:void-paid',
      '{"validation_fixture":true}'::jsonb
    );
    raise exception 'Paid/reopened obligation was incorrectly voided.';
  exception when sqlstate '23514' then
    null;
  end;

  -- The existing current Flower v2 writer must remain the Package 4 implementation,
  -- not be replaced by the superseded Money PR's old v2 wrapper.
  select pg_get_functiondef(p.oid) into v_definition
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='atlas' and p.proname='record_flower_sale_core_v2'
  limit 1;
  if v_definition is null or position('cancellation_and_disposition_aware_v1' in v_definition)=0 then
    raise exception 'Current Flower Sale v2 writer was replaced or lost.';
  end if;

  if has_table_privilege('authenticated','atlas.money_obligations','SELECT')
     or has_table_privilege('authenticated','atlas.money_receipts','SELECT')
     or has_table_privilege('service_role','atlas.money_obligations','INSERT')
     or has_table_privilege('service_role','atlas.money_receipts','INSERT') then
    raise exception 'Direct Money table privilege leaked to a browser/service role.';
  end if;

  if has_function_privilege(
       'authenticated',
       'atlas.ensure_money_obligation_core_v1(uuid,uuid,text,text,text,text,numeric,text,timestamptz,timestamptz,text,jsonb)',
       'EXECUTE'
     )
     or has_function_privilege(
       'service_role',
       'atlas.record_money_receipt_core_v1(uuid,uuid,numeric,text,timestamptz,text,text,text,uuid,uuid,text,jsonb)',
       'EXECUTE'
     ) then
    raise exception 'Internal Money mutation function is executable outside database custody.';
  end if;

  if not has_function_privilege(
       'authenticated','public.money_positions_self_api_v1(uuid)','EXECUTE'
     )
     or has_function_privilege(
       'anon','public.money_positions_self_api_v1(uuid)','EXECUTE'
     ) then
    raise exception 'Money browser read privilege boundary is incorrect.';
  end if;

  if not exists(
    select 1 from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas' and c.relname='flower_sale_orders'
      and t.tgname='flower_sale_money_obligation_v1' and not t.tgisinternal
  ) or not exists(
    select 1 from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas' and c.relname='community_registrations'
      and t.tgname='community_registration_money_obligation_v1' and not t.tgisinternal
  ) or not exists(
    select 1 from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas' and c.relname='community_registration_payments'
      and t.tgname='community_registration_payment_money_v1' and not t.tgisinternal
  ) then
    raise exception 'One or more source-to-Money governed adapters are missing.';
  end if;
end;
$money_postconditions$;
