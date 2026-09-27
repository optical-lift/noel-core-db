-- Contract validation: account-centered review + Spend promotion v2

begin;

do $$
declare
  v_def text;
  v_nullable text;
begin
  if to_regprocedure('atlas.replace_financial_source_transaction_review_self_api_v2(uuid,text,jsonb,jsonb)') is null then
    raise exception 'Missing replace_financial_source_transaction_review_self_api_v2';
  end if;
  if to_regprocedure('atlas.financial_source_transaction_review_window_self_api_v2(date,date)') is null then
    raise exception 'Missing financial_source_transaction_review_window_self_api_v2';
  end if;
  if to_regprocedure('atlas.promote_financial_source_transaction_expense_self_api_v2(uuid,uuid)') is null then
    raise exception 'Missing promote_financial_source_transaction_expense_self_api_v2';
  end if;

  if not exists(
    select 1 from information_schema.columns
    where table_schema='atlas' and table_name='financial_source_transaction_review_events'
      and column_name='financial_evidence_observation_id'
  ) then
    raise exception 'Review events must bind account-centered evidence observations';
  end if;
  select is_nullable into v_nullable
  from information_schema.columns
  where table_schema='atlas' and table_name='financial_source_transaction_review_events'
    and column_name='source_observation_id';
  if v_nullable<>'YES' then
    raise exception 'Account-centered reviews must not require a connected-source observation';
  end if;

  select pg_get_functiondef('atlas.replace_financial_source_transaction_review_self_api_v2(uuid,text,jsonb,jsonb)'::regprocedure)
  into v_def;
  if position('fullAmountAccounted' in v_def)=0
     or position('current_financial_evidence_observation_id' in v_def)=0
     or position('financial_source_account_authorized_self_v2' in v_def)=0 then
    raise exception 'V2 review must be full-amount, current-evidence-bound, and account-authorized';
  end if;
  if position('financial_connected_source_authorized_self_v1' in v_def)>0 then
    raise exception 'V2 review must not require externally authorized connector custody';
  end if;

  select pg_get_functiondef('atlas.promote_financial_source_transaction_expense_self_api_v2(uuid,uuid)'::regprocedure)
  into v_def;
  if position('ledger.ledgers' in v_def)=0
     or position('subject_entity_id' in v_def)=0 then
    raise exception 'V2 Spend promotion must use canonical Ledger subject';
  end if;
  if position('financial_source_account_reality_holders' in v_def)=0 then
    raise exception 'V2 Spend promotion must use Reality financial account holders';
  end if;
  if position('cross_entity_account_holder_requires_governed_reporting_or_funding_relation' in v_def)=0 then
    raise exception 'Cross-entity account ownership must fail closed instead of becoming external funding automatically';
  end if;
  if position("v_funding_kind:='external_party'" in v_def)>0 then
    raise exception 'V2 Spend promotion must not infer external-party funding solely from a different account holder entity';
  end if;
  if position('financial_source_evidence_projection' in v_def)=0
     or position('rawObservedSnapshotRemainsInSourceEvidenceRecord' in v_def)=0 then
    raise exception 'Ledger Spend evidence must project from, not duplicate, account source evidence';
  end if;
  if position('compatibility.legacy_bindings' in v_def)=0
     or position('compatibilityOrganizationIsRoutingOnly' in v_def)=0 then
    raise exception 'Legacy organization use must remain a routing-only Package 5 adapter';
  end if;

  if to_regprocedure('atlas.replace_financial_source_transaction_review_self_api_v1(uuid,text,jsonb,jsonb)') is null
     or to_regprocedure('atlas.promote_financial_source_transaction_expense_self_api_v1(uuid,uuid)') is null then
    raise exception 'V2 account-centered path must not remove the existing connector-centered V1 path';
  end if;
end;
$$;

rollback;
