begin;

do $validation$
declare
  v_receipt jsonb;
  v_def text;
begin
  -- Normalizer fails closed on malformed cross-domain receipts.
  begin
    perform atlas.reality_transition_receipt_normalize_v1(
      '{"receiptKind":"bad","source":{},"subject":{},"resolution":{"state":"effective","resolver":"x"},"continuation":{},"provenance":{}}'::jsonb
    );
    raise exception 'Normalizer accepted an incomplete source/subject identity.';
  exception
    when sqlstate '22023' then null;
  end;

  begin
    perform atlas.reality_transition_receipt_normalize_v1(
      '{"receiptKind":"bad","source":{"domain":"x","kind":"y","ref":"z"},"subject":{"kind":"x","ref":"y","scope":{}},"resolution":{"state":"made_up","resolver":"x"},"continuation":{},"provenance":{}}'::jsonb
    );
    raise exception 'Normalizer accepted an unsupported resolution state.';
  exception
    when sqlstate '22023' then null;
  end;

  -- Company Work effective chain keeps report, acceptance, terminal Work and
  -- Ledger consequence distinct.
  v_receipt:=atlas.company_work_result_transition_receipt_v1(
    'f4800000-0000-4000-8000-000000000111'::uuid
  );

  if v_receipt->>'contractVersion'<>'reality_transition_receipt_v1'
     or v_receipt->>'receiptKind'<>'company_work_result'
     or v_receipt#>>'{source,kind}'<>'work_execution_result'
     or v_receipt#>>'{resolution,state}'<>'effective'
     or v_receipt#>>'{consequence,kind}'<>'organization_ledger_entry'
     or v_receipt#>>'{consequence,state}'<>'established'
     or v_receipt#>>'{resolution,details,acceptanceDecision}'<>'accepted'
     or v_receipt#>>'{resolution,details,workState}'<>'completed'
     or jsonb_array_length(v_receipt#>'{interpretation,actualRefs}')<>1
     or jsonb_array_length(v_receipt#>'{resolution,basisRefs}')<>3 then
    raise exception 'Effective Company Work transition receipt is incorrect: %',v_receipt;
  end if;

  if not exists (
    select 1
    from jsonb_array_elements_text(v_receipt#>'{continuation,blockers}') x(value)
  ) and jsonb_array_length(v_receipt#>'{continuation,blockers}')<>0 then
    raise exception 'Effective Company Work receipt has malformed blockers.';
  end if;

  -- Reported result with no adjudication remains unresolved.
  v_receipt:=atlas.company_work_result_transition_receipt_v1(
    'f4800000-0000-4000-8000-000000000112'::uuid
  );

  if v_receipt#>>'{resolution,state}'<>'unresolved'
     or not (v_receipt#>'{continuation,blockers}' @> '["result_acceptance_missing"]'::jsonb)
     or not (v_receipt#>'{continuation,reconsider}' @> '["company_work_result_adjudication"]'::jsonb)
     or v_receipt ? 'consequence' then
    raise exception 'Unadjudicated Company Work result did not remain unresolved: %',v_receipt;
  end if;

  -- Explicit rejection remains a historical result but produces rejected
  -- resolution, not a completion consequence.
  v_receipt:=atlas.company_work_result_transition_receipt_v1(
    'f4800000-0000-4000-8000-000000000113'::uuid
  );

  if v_receipt#>>'{resolution,state}'<>'rejected'
     or v_receipt#>>'{resolution,details,acceptanceDecision}'<>'rejected'
     or v_receipt ? 'consequence' then
    raise exception 'Rejected Company Work result was collapsed into a consequence: %',v_receipt;
  end if;

  -- Paid commercial order derives Financial Reality from order/payment evidence.
  v_receipt:=atlas.commercial_financial_transition_receipt_v1(
    'f4800000-0000-4000-8000-000000000201'::uuid
  );

  if v_receipt->>'receiptKind'<>'commercial_financial_position'
     or v_receipt#>>'{resolution,state}'<>'effective'
     or v_receipt#>>'{consequence,kind}'<>'commercial_financial_position'
     or v_receipt#>>'{consequence,state}'<>'paid'
     or (v_receipt#>>'{consequence,details,netCollectedAmount}')::numeric<>100
     or (v_receipt#>>'{consequence,details,openAmount}')::numeric<>0
     or jsonb_array_length(v_receipt#>'{provenance,independentFulfillmentRefs}')<>1
     or coalesce((v_receipt#>>'{provenance,fulfillmentExcludedFromFinancialResolution}')::boolean,false)=false then
    raise exception 'Paid Commercial Financial receipt is incorrect: %',v_receipt;
  end if;

  if not exists (
    select 1
    from jsonb_array_elements(v_receipt#>'{interpretation,actualRefs}') x(value)
    where x.value->>'kind'='commercial_payment_event'
      and x.value->>'eventKind'='succeeded'
  ) then
    raise exception 'Paid receipt lost payment-event Actual evidence.';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(v_receipt#>'{interpretation,actualRefs}') x(value)
    where x.value->>'kind'='commercial_fulfillment_event'
  ) then
    raise exception 'Fulfillment was incorrectly admitted as Financial Reality evidence.';
  end if;

  -- Fulfillment does not make an unpaid governed order paid.
  v_receipt:=atlas.commercial_financial_transition_receipt_v1(
    'f4800000-0000-4000-8000-000000000202'::uuid
  );

  if v_receipt#>>'{resolution,state}'<>'effective'
     or v_receipt#>>'{consequence,state}'<>'open'
     or not (v_receipt#>'{continuation,reconsider}' @> '["commercial_collection_or_settlement"]'::jsonb)
     or jsonb_array_length(v_receipt#>'{provenance,independentFulfillmentRefs}')<>1 then
    raise exception 'Fulfilled-but-open commercial order was collapsed into settlement: %',v_receipt;
  end if;

  -- Historical commercial order with unknown collection coverage remains
  -- unresolved rather than becoming a fabricated receivable.
  v_receipt:=atlas.commercial_financial_transition_receipt_v1(
    'f4800000-0000-4000-8000-000000000203'::uuid
  );

  if v_receipt#>>'{resolution,state}'<>'unresolved'
     or v_receipt#>>'{consequence,state}'<>'collection_unknown'
     or not (v_receipt#>'{continuation,blockers}' @> '["collection_evidence_unknown"]'::jsonb)
     or not (v_receipt#>'{continuation,reconsider}' @> '["commercial_financial_reconciliation"]'::jsonb) then
    raise exception 'Historical unknown collection was fabricated into settled/open truth: %',v_receipt;
  end if;

  -- There is deliberately no generic Transition Receipt storage.
  if to_regclass('atlas.reality_transition_receipts') is not null
     or to_regclass('atlas.reality_transitions') is not null
     or to_regclass('atlas.transition_events') is not null then
    raise exception 'Reality Transition Receipt candidate introduced forbidden generic storage.';
  end if;

  -- Cross-domain adapters stay internal. Generic read authority must be
  -- established later by domain/custody-specific membranes.
  if has_function_privilege(
       'authenticated',
       'atlas.reality_transition_receipt_normalize_v1(jsonb)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.company_work_result_transition_receipt_v1(uuid)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.commercial_financial_transition_receipt_v1(uuid)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'atlas.reality_transition_receipt_normalize_v1(jsonb)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'atlas.company_work_result_transition_receipt_v1(uuid)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'atlas.commercial_financial_transition_receipt_v1(uuid)',
       'EXECUTE'
     ) then
    raise exception 'Generic Reality Transition Receipt functions leaked to browser roles.';
  end if;

  -- Static mutation boundary: adapters may compose reads but never become
  -- transition writers.
  select lower(pg_get_functiondef(
    'atlas.company_work_result_transition_receipt_v1(uuid)'::regprocedure
  )) into v_def;

  if v_def like '%insert into%'
     or v_def like '%update atlas.%'
     or v_def like '%delete from%'
     or v_def like '%perform atlas.%'
     or v_def like '%execute %' then
    raise exception 'Company Work transition receipt adapter contains mutation authority.';
  end if;

  select lower(pg_get_functiondef(
    'atlas.commercial_financial_transition_receipt_v1(uuid)'::regprocedure
  )) into v_def;

  if v_def like '%insert into%'
     or v_def like '%update atlas.%'
     or v_def like '%delete from%'
     or v_def like '%perform atlas.%'
     or v_def like '%execute %' then
    raise exception 'Commercial transition receipt adapter contains mutation authority.';
  end if;

  select lower(pg_get_functiondef(
    'atlas.reality_transition_receipt_normalize_v1(jsonb)'::regprocedure
  )) into v_def;

  if v_def like '%select %from atlas.%'
     or v_def like '%insert into%'
     or v_def like '%update atlas.%'
     or v_def like '%delete from%' then
    raise exception 'Transition Receipt normalizer escaped schema-only authority.';
  end if;
end;
$validation$;

rollback;
