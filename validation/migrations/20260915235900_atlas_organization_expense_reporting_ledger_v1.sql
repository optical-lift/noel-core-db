-- Postconditions for Atlas Organization Expense Reporting — Ledger-Custodied v1.

-- Root Principal A configures a CI-like contract. Category meaning and export
-- label are deliberately distinct, and Printing/Publishing is not invented.
do $$
declare
  v_result jsonb;
  v_contract_id uuid;
  v_hospitality uuid;
  v_goodwill uuid;
  v_printing uuid;
begin
  perform set_config('request.jwt.claim.sub','95359000-0000-4000-8000-000000000001',true);

  v_result:=atlas.configure_organization_expense_reporting_contract_self_api_v1(
    '95359000-0000-4000-8000-000000000040'::uuid,
    '95359000-0000-4000-8000-000000000010'::uuid,
    '95359000-0000-4000-8000-000000000020'::uuid,
    'ci_mexico_monthly',
    'Camps International Mexico Monthly Expense Report',
    'Camps International',
    'monthly','USD','2026-01-01',null,
    '[
      {"categoryKey":"hospitality_lodging","canonicalLabel":"Hospitality/Lodging","exportLabel":"Hospitality/Lodging/Meals","evidenceRules":{"requiresReceipt":true},"mappingState":"confirmed","sortOrder":10},
      {"categoryKey":"goodwill","canonicalLabel":"Goodwill","exportLabel":"Goodwill/C/H","evidenceRules":{},"mappingState":"confirmed","sortOrder":20},
      {"categoryKey":"printing","canonicalLabel":"Printing","exportLabel":null,"evidenceRules":{},"mappingState":"unresolved","sortOrder":30}
    ]'::jsonb,
    '{"expense":{"requiredFieldKey":"mexicanFactura"}}'::jsonb,
    '{"destination":"quickbooks","postingGrain":"category_subtotal","detailArtifactRequired":true}'::jsonb,
    'validation_fixture_policy',null,'validation_fixture_template',null,
    '{"validation_fixture":true}'::jsonb
  );

  v_contract_id:=(v_result->>'contractId')::uuid;
  select id into v_hospitality from atlas.organization_expense_reporting_categories where contract_id=v_contract_id and category_key='hospitality_lodging';
  select id into v_goodwill from atlas.organization_expense_reporting_categories where contract_id=v_contract_id and category_key='goodwill';
  select id into v_printing from atlas.organization_expense_reporting_categories where contract_id=v_contract_id and category_key='printing';

  if v_result->>'reportCurrency'<>'USD' or (v_result->>'categoryCount')::int<>3 then
    raise exception 'Reporting contract configuration failed.';
  end if;

  if not exists(
    select 1 from atlas.organization_expense_reporting_categories
    where id=v_hospitality and canonical_label='Hospitality/Lodging' and export_label='Hospitality/Lodging/Meals'
  ) then raise exception 'Hospitality meaning/export label distinction was lost.'; end if;

  if not exists(
    select 1 from atlas.organization_expense_reporting_categories
    where id=v_goodwill and canonical_label='Goodwill' and export_label='Goodwill/C/H'
  ) then raise exception 'Goodwill meaning/export label distinction was lost.'; end if;

  if not exists(
    select 1 from atlas.organization_expense_reporting_categories
    where id=v_printing and canonical_label='Printing' and export_label is null and mapping_state='unresolved'
  ) then raise exception 'Unresolved Printing/Publishing mapping was silently manufactured.'; end if;
end;
$$;

-- Foreign Principal cannot configure another Ledger's reporting contract.
do $$
begin
  perform set_config('request.jwt.claim.sub','95359000-0000-4000-8000-000000000002',true);
  begin
    perform atlas.configure_organization_expense_reporting_contract_self_api_v1(
      '95359000-0000-4000-8000-000000000040'::uuid,
      '95359000-0000-4000-8000-000000000010'::uuid,
      null,'foreign_attempt','Foreign','Foreign','monthly','USD','2026-01-01',null,
      '[]'::jsonb,'{}'::jsonb,'{}'::jsonb,null,null,null,null,'{}'::jsonb
    );
    raise exception 'Foreign Principal unexpectedly configured reporting contract.';
  exception when sqlstate '42501' then null;
  end;
end;
$$;

-- Principal A opens September reporting period.
do $$
declare
  v_contract_id uuid;
  v_result jsonb;
  v_period_id uuid;
begin
  perform set_config('request.jwt.claim.sub','95359000-0000-4000-8000-000000000001',true);
  select id into v_contract_id from atlas.organization_expense_reporting_contracts where ledger_id='95359000-0000-4000-8000-000000000040'::uuid and contract_key='ci_mexico_monthly';
  v_result:=atlas.open_organization_expense_reporting_period_self_api_v1(
    v_contract_id,
    '95359000-0000-4000-8000-000000000020'::uuid,
    '2026-09-01','2026-09-30',
    '{"country":"Mexico","month":"2026-09"}'::jsonb,
    '{"validation_fixture":true}'::jsonb
  );
  v_period_id:=(v_result->>'periodId')::uuid;
  if v_result->>'state'<>'opened' or v_period_id is null then raise exception 'Reporting period was not opened.'; end if;
end;
$$;

-- Once a contract version has a period, configuration is immutable.
do $$
begin
  perform set_config('request.jwt.claim.sub','95359000-0000-4000-8000-000000000001',true);
  begin
    perform atlas.configure_organization_expense_reporting_contract_self_api_v1(
      '95359000-0000-4000-8000-000000000040'::uuid,
      '95359000-0000-4000-8000-000000000010'::uuid,
      '95359000-0000-4000-8000-000000000020'::uuid,
      'ci_mexico_monthly','Changed Name','Camps International','monthly','USD','2026-01-01',null,
      '[]'::jsonb,'{}'::jsonb,'{}'::jsonb,null,null,null,null,'{}'::jsonb
    );
    raise exception 'Used reporting contract version unexpectedly mutated.';
  exception when sqlstate '55000' then null;
  end;
end;
$$;

-- Admit the MXN accommodation as included/confirmed/reimbursable before rate
-- or receipt evidence exists. Current-state exceptions must be deterministic.
do $$
declare
  v_period uuid;
  v_category uuid;
  v_result jsonb;
  v_blocking integer;
  v_warning integer;
begin
  perform set_config('request.jwt.claim.sub','95359000-0000-4000-8000-000000000001',true);
  select p.id into v_period from atlas.organization_expense_reporting_periods p join atlas.organization_expense_reporting_contracts c on c.id=p.contract_id where c.contract_key='ci_mexico_monthly' and p.period_start='2026-09-01';
  select c.id into v_category from atlas.organization_expense_reporting_categories c join atlas.organization_expense_reporting_contracts con on con.id=c.contract_id where con.contract_key='ci_mexico_monthly' and c.category_key='hospitality_lodging';

  v_result:=atlas.interpret_organization_spend_for_expense_report_self_api_v1(
    v_period,
    '95359000-0000-4000-8000-000000000101'::uuid,
    'interpret-hotel-1','included','reimbursement',v_category,'confirmed',1,
    'Hotel accommodation','{}'::jsonb,'{"validation_fixture":true}'::jsonb
  );

  select count(*) filter(where severity='blocking'),count(*) filter(where severity='warning')
  into v_blocking,v_warning
  from atlas.organization_expense_reporting_exception_position_v1
  where fact_link_id=(v_result->>'factLinkId')::uuid;

  if v_blocking<>2 or v_warning<>1 then
    raise exception 'Expected two blocking exceptions (rate + receipt) and one configured-field warning, got % / %.',v_blocking,v_warning;
  end if;

  if not exists(select 1 from atlas.organization_expense_reporting_exception_position_v1 where fact_link_id=(v_result->>'factLinkId')::uuid and exception_code='exchange_rate_missing')
     or not exists(select 1 from atlas.organization_expense_reporting_exception_position_v1 where fact_link_id=(v_result->>'factLinkId')::uuid and exception_code='receipt_required_missing')
     or not exists(select 1 from atlas.organization_expense_reporting_exception_position_v1 where fact_link_id=(v_result->>'factLinkId')::uuid and exception_code='template_field_state_missing') then
    raise exception 'Expected current-state reporting exceptions are incomplete.';
  end if;

  begin
    perform atlas.mark_organization_expense_reporting_period_ready_self_api_v1(v_period);
    raise exception 'Period unexpectedly became ready with blocking exceptions.';
  exception when sqlstate '55000' then null;
  end;
end;
$$;

-- A foreign-Ledger Spend allocation cannot enter this reporting period.
do $$
declare
  v_period uuid;
begin
  perform set_config('request.jwt.claim.sub','95359000-0000-4000-8000-000000000001',true);
  select id into v_period from atlas.organization_expense_reporting_periods where ledger_id='95359000-0000-4000-8000-000000000040'::uuid and period_start='2026-09-01';
  begin
    perform atlas.interpret_organization_spend_for_expense_report_self_api_v1(
      v_period,'95359000-0000-4000-8000-000000000121'::uuid,'foreign-allocation','included','organization_paid',null,'unclassified',null,null,'{}'::jsonb,'{}'::jsonb
    );
    raise exception 'Foreign-Ledger Spend allocation unexpectedly entered report.';
  exception when sqlstate 'P0002' then null;
  end;
end;
$$;

-- Explicit quote direction normalizes 16.5 MXN per USD to 1/16.5.
do $$
declare
  v_period uuid;
  v_result jsonb;
  v_multiplier numeric;
  v_blocking integer;
begin
  perform set_config('request.jwt.claim.sub','95359000-0000-4000-8000-000000000001',true);
  select id into v_period from atlas.organization_expense_reporting_periods where ledger_id='95359000-0000-4000-8000-000000000040'::uuid and period_start='2026-09-01';

  v_result:=atlas.set_organization_expense_reporting_rate_self_api_v1(
    v_period,'mxn_usd_monthly','MXN','USD',16.5,'source_units_per_one_reporting_unit',
    '2026-09-01','2026-09-30','organization_provided','CI fixture quote','2026-09-01 12:00:00+00','{"validation_fixture":true}'::jsonb
  );
  v_multiplier:=(v_result->>'conversionMultiplier')::numeric;
  if round(v_multiplier,10)<>round((1::numeric/16.5::numeric),10) then raise exception 'Explicit rate direction normalized incorrectly.'; end if;

  select count(*) into v_blocking from atlas.organization_expense_reporting_exception_position_v1 e
  join atlas.organization_expense_reporting_fact_links f on f.id=e.fact_link_id
  where f.spend_allocation_id='95359000-0000-4000-8000-000000000101'::uuid and e.severity='blocking';
  if v_blocking<>1 or exists(
    select 1 from atlas.organization_expense_reporting_exception_position_v1 e
    join atlas.organization_expense_reporting_fact_links f on f.id=e.fact_link_id
    where f.spend_allocation_id='95359000-0000-4000-8000-000000000101'::uuid and e.exception_code='exchange_rate_missing'
  ) then raise exception 'Rate exception did not disappear after current rate state was established.'; end if;
end;
$$;

-- A second overlapping accepted rate makes conversion ambiguous; narrowing its
-- effective window removes the ambiguity without an exception-history mutation.
do $$
declare
  v_period uuid;
  v_fact uuid;
begin
  perform set_config('request.jwt.claim.sub','95359000-0000-4000-8000-000000000001',true);
  select id into v_period from atlas.organization_expense_reporting_periods where ledger_id='95359000-0000-4000-8000-000000000040'::uuid and period_start='2026-09-01';
  select id into v_fact from atlas.organization_expense_reporting_fact_links where spend_allocation_id='95359000-0000-4000-8000-000000000101'::uuid;

  perform atlas.set_organization_expense_reporting_rate_self_api_v1(
    v_period,'mxn_usd_alternate','MXN','USD',17,'source_units_per_one_reporting_unit',
    '2026-09-01','2026-09-30','organization_provided','alternate fixture','2026-09-01 13:00:00+00','{}'::jsonb
  );
  if not exists(select 1 from atlas.organization_expense_reporting_exception_position_v1 where fact_link_id=v_fact and exception_code='exchange_rate_ambiguous') then
    raise exception 'Overlapping rates did not create ambiguity.';
  end if;

  perform atlas.set_organization_expense_reporting_rate_self_api_v1(
    v_period,'mxn_usd_alternate','MXN','USD',17,'source_units_per_one_reporting_unit',
    '2026-09-01','2026-09-14','organization_provided','alternate fixture','2026-09-01 13:00:00+00','{}'::jsonb
  );
  if exists(select 1 from atlas.organization_expense_reporting_exception_position_v1 where fact_link_id=v_fact and exception_code='exchange_rate_ambiguous') then
    raise exception 'Rate ambiguity did not disappear when current effective windows stopped overlapping.';
  end if;
end;
$$;

-- Link canonical receipt Evidence to Spend. The reporting receipt exception
-- must disappear because Evidence changed, without copying receipt truth.
do $$
declare
  v_link uuid;
  v_fact uuid;
  v_blocking integer;
begin
  v_link:=atlas.link_organization_spend_evidence_core_v1(
    '95359000-0000-4000-8000-000000000040'::uuid,
    '95359000-0000-4000-8000-000000000010'::uuid,
    '95359000-0000-4000-8000-000000000100'::uuid,
    '95359000-0000-4000-8000-000000000101'::uuid,
    '95359000-0000-4000-8000-000000000130'::uuid,
    'receipt',
    '95359000-0000-4000-8000-000000000050'::uuid,
    '95359000-0000-4000-8000-000000000030'::uuid,
    '{"validation_fixture":true}'::jsonb
  );
  if v_link is null then raise exception 'Canonical Spend Evidence link was not established.'; end if;
  select id into v_fact from atlas.organization_expense_reporting_fact_links where spend_allocation_id='95359000-0000-4000-8000-000000000101'::uuid;
  if exists(select 1 from atlas.organization_expense_reporting_exception_position_v1 where fact_link_id=v_fact and exception_code='receipt_required_missing') then
    raise exception 'Receipt exception did not disappear after canonical Spend Evidence became sufficient.';
  end if;
  select count(*) into v_blocking from atlas.organization_expense_reporting_exception_position_v1 where fact_link_id=v_fact and severity='blocking';
  if v_blocking<>0 then raise exception 'Hotel fact still has unexpected blocking exceptions after rate + receipt resolution.'; end if;
end;
$$;

-- Admit the USD goodwill line. It needs no exchange rate and keeps export label
-- separate from category meaning.
do $$
declare
  v_period uuid;
  v_category uuid;
  v_result jsonb;
  v_amount numeric;
begin
  perform set_config('request.jwt.claim.sub','95359000-0000-4000-8000-000000000001',true);
  select id into v_period from atlas.organization_expense_reporting_periods where ledger_id='95359000-0000-4000-8000-000000000040'::uuid and period_start='2026-09-01';
  select id into v_category from atlas.organization_expense_reporting_categories where contract_id=(select contract_id from atlas.organization_expense_reporting_periods where id=v_period) and category_key='goodwill';

  v_result:=atlas.interpret_organization_spend_for_expense_report_self_api_v1(
    v_period,'95359000-0000-4000-8000-000000000103'::uuid,
    'interpret-goodwill-1','included','organization_paid',v_category,'confirmed',1,
    null,'{"mexicanFactura":false}'::jsonb,'{"validation_fixture":true}'::jsonb
  );
  select report_amount into v_amount from atlas.organization_expense_reporting_expense_lines_v1 where fact_link_id=(v_result->>'factLinkId')::uuid;
  if v_amount<>50 then raise exception 'Same-currency reporting amount should remain 50 USD.'; end if;
end;
$$;

-- 1,650 MXN converts to 100 USD; category totals reconcile to 150 USD.
do $$
declare
  v_hotel numeric;
  v_total numeric;
  v_groups integer;
  v_handoff jsonb;
  v_period uuid;
begin
  select report_amount into v_hotel from atlas.organization_expense_reporting_expense_lines_v1 where spend_allocation_id='95359000-0000-4000-8000-000000000101'::uuid;
  if round(v_hotel,2)<>100.00 then raise exception '1,650 MXN did not convert to 100 USD.'; end if;
  select round(sum(report_subtotal),2),count(*) into v_total,v_groups from atlas.organization_expense_reporting_category_totals_v1 where period_id=(select id from atlas.organization_expense_reporting_periods where ledger_id='95359000-0000-4000-8000-000000000040'::uuid and period_start='2026-09-01');
  if v_total<>150.00 or v_groups<>2 then raise exception 'Category totals did not reconcile to two groups / 150 USD.'; end if;

  perform set_config('request.jwt.claim.sub','95359000-0000-4000-8000-000000000001',true);
  select id into v_period from atlas.organization_expense_reporting_periods where ledger_id='95359000-0000-4000-8000-000000000040'::uuid and period_start='2026-09-01';
  v_handoff:=atlas.organization_expense_reporting_accounting_handoff_self_api_v1(v_period);
  if round((v_handoff->>'reportExpenseTotal')::numeric,2)<>150.00 or jsonb_array_length(v_handoff->'detailGroups')<>2 then
    raise exception 'Accounting handoff did not reconcile to 150 USD across two category groups.';
  end if;
end;
$$;

-- Only a warning remains, so the period can become ready. Then reopen it,
-- resolve the configured field by changing present interpretation state, and
-- become ready again with zero exceptions.
do $$
declare
  v_period uuid;
  v_hotel_fact uuid;
  v_hospitality uuid;
  v_result jsonb;
  v_events integer;
begin
  perform set_config('request.jwt.claim.sub','95359000-0000-4000-8000-000000000001',true);
  select id into v_period from atlas.organization_expense_reporting_periods where ledger_id='95359000-0000-4000-8000-000000000040'::uuid and period_start='2026-09-01';
  select id,category_id into v_hotel_fact,v_hospitality from atlas.organization_expense_reporting_fact_links where spend_allocation_id='95359000-0000-4000-8000-000000000101'::uuid;

  if (select count(*) from atlas.organization_expense_reporting_exception_position_v1 where period_id=v_period and severity='blocking')<>0 then raise exception 'Blocking exceptions remain before ready transition.'; end if;
  if (select count(*) from atlas.organization_expense_reporting_exception_position_v1 where period_id=v_period and severity='warning')<>1 then raise exception 'Expected one nonblocking configured-field warning before first ready transition.'; end if;

  v_result:=atlas.mark_organization_expense_reporting_period_ready_self_api_v1(v_period);
  if v_result->>'state'<>'ready' then raise exception 'Period did not become ready.'; end if;
  perform atlas.reopen_organization_expense_reporting_period_self_api_v1(v_period);

  v_result:=atlas.interpret_organization_spend_for_expense_report_self_api_v1(
    v_period,'95359000-0000-4000-8000-000000000101'::uuid,
    'interpret-hotel-2','included','reimbursement',v_hospitality,'confirmed',1,
    'Hotel accommodation','{"mexicanFactura":true}'::jsonb,'{"validation_fixture":true}'::jsonb
  );
  if exists(select 1 from atlas.organization_expense_reporting_exception_position_v1 where fact_link_id=v_hotel_fact) then raise exception 'Current-state exceptions did not disappear after underlying interpretation was completed.'; end if;

  -- Exact event-key replay must not append history.
  v_result:=atlas.interpret_organization_spend_for_expense_report_self_api_v1(
    v_period,'95359000-0000-4000-8000-000000000101'::uuid,
    'interpret-hotel-2','included','reimbursement',v_hospitality,'confirmed',1,
    'Hotel accommodation','{"mexicanFactura":true}'::jsonb,'{"validation_fixture":true}'::jsonb
  );
  if v_result->>'state'<>'unchanged' then raise exception 'Interpretation event retry is not idempotent.'; end if;
  select count(*) into v_events from atlas.organization_expense_reporting_fact_events where fact_link_id=v_hotel_fact;
  if v_events<>2 then raise exception 'Interpretation history should contain exactly admission + one update.'; end if;

  perform atlas.mark_organization_expense_reporting_period_ready_self_api_v1(v_period);
  if (select state from atlas.organization_expense_reporting_periods where id=v_period)<>'ready' then raise exception 'Final reporting period did not return to ready.'; end if;
end;
$$;

-- Reusing an existing client event key for another fact must fail, not silently
-- return the first fact's receipt.
do $$
declare
  v_period uuid;
  v_goodwill uuid;
begin
  perform set_config('request.jwt.claim.sub','95359000-0000-4000-8000-000000000001',true);
  select id into v_period from atlas.organization_expense_reporting_periods where ledger_id='95359000-0000-4000-8000-000000000040'::uuid and period_start='2026-09-01';
  perform atlas.reopen_organization_expense_reporting_period_self_api_v1(v_period);
  select category_id into v_goodwill from atlas.organization_expense_reporting_fact_links where spend_allocation_id='95359000-0000-4000-8000-000000000103'::uuid;
  begin
    perform atlas.interpret_organization_spend_for_expense_report_self_api_v1(
      v_period,'95359000-0000-4000-8000-000000000103'::uuid,
      'interpret-hotel-2','included','organization_paid',v_goodwill,'confirmed',1,
      'Community goodwill','{"mexicanFactura":false}'::jsonb,'{}'::jsonb
    );
    raise exception 'Conflicting interpretation event key unexpectedly succeeded.';
  exception when sqlstate '23514' then null;
  end;
  perform atlas.mark_organization_expense_reporting_period_ready_self_api_v1(v_period);
end;
$$;

-- Interpretation event history is append-only.
do $$
declare
  v_event uuid;
begin
  select id into v_event from atlas.organization_expense_reporting_fact_events order by created_at,id limit 1;
  begin
    update atlas.organization_expense_reporting_fact_events set metadata='{"mutated":true}'::jsonb where id=v_event;
    raise exception 'Expense reporting history mutation unexpectedly succeeded.';
  exception when sqlstate '55000' then null;
  end;
end;
$$;

-- Root-Ledger authority gates period reads and accounting handoff.
do $$
declare
  v_period uuid;
  v_payload jsonb;
begin
  select id into v_period from atlas.organization_expense_reporting_periods where ledger_id='95359000-0000-4000-8000-000000000040'::uuid and period_start='2026-09-01';
  perform set_config('request.jwt.claim.sub','95359000-0000-4000-8000-000000000001',true);
  v_payload:=atlas.organization_expense_reporting_period_self_api_v1(v_period);
  if jsonb_array_length(v_payload->'expenseLines')<>2 or (v_payload->>'blockingExceptionCount')::int<>0 then raise exception 'Authorized reporting period read is incorrect.'; end if;

  perform set_config('request.jwt.claim.sub','95359000-0000-4000-8000-000000000002',true);
  begin
    perform atlas.organization_expense_reporting_period_self_api_v1(v_period);
    raise exception 'Foreign Principal unexpectedly read reporting period.';
  exception when sqlstate '42501' then null;
  end;
end;
$$;

-- Direct table/view access remains closed. Browser access is through explicit
-- root-Ledger self APIs only.
do $$
begin
  if has_table_privilege('authenticated','atlas.organization_expense_reporting_contracts','SELECT')
     or has_table_privilege('authenticated','atlas.organization_expense_reporting_fact_links','INSERT')
     or has_table_privilege('service_role','atlas.organization_expense_reporting_contracts','SELECT')
     or has_table_privilege('service_role','atlas.organization_expense_reporting_fact_links','INSERT') then
    raise exception 'Direct expense-reporting table privilege leaked.';
  end if;
  if has_table_privilege('authenticated','atlas.organization_expense_reporting_expense_lines_v1','SELECT')
     or has_table_privilege('service_role','atlas.organization_expense_reporting_exception_position_v1','SELECT') then
    raise exception 'Direct expense-reporting view privilege leaked.';
  end if;
  if not has_function_privilege('authenticated','atlas.organization_expense_reporting_period_self_api_v1(uuid)','EXECUTE')
     or has_function_privilege('anon','atlas.organization_expense_reporting_period_self_api_v1(uuid)','EXECUTE')
     or has_function_privilege('service_role','atlas.organization_expense_reporting_period_self_api_v1(uuid)','EXECUTE') then
    raise exception 'Expense-reporting read membrane privileges are incorrect.';
  end if;
end;
$$;

-- Released upstream financial objects remain intact.
do $$
begin
  if to_regclass('atlas.organization_spend_occurrences') is null
     or to_regclass('atlas.organization_spend_position_v1') is null
     or to_regclass('atlas.commercial_financial_position_v1') is null then
    raise exception 'Released Spend or Commercial Financial Reality objects disappeared.';
  end if;
  if to_regprocedure('atlas.record_flower_sale_core_v2(uuid,uuid,text,uuid,text,text,text,jsonb,numeric,numeric,text,date,time without time zone,uuid,uuid,text,text,boolean)') is null then
    raise exception 'Current Package-4 Flower Sale v2 writer disappeared.';
  end if;
end;
$$;
