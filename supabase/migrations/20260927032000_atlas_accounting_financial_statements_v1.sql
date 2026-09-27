-- Accounting financial statement reads v1.
-- Posted journal entries only. These are reporting projections, never source or Reality truth.

create or replace function atlas.accounting_profit_and_loss_self_api_v1(
  p_accounting_book_id uuid,
  p_start_on date,
  p_end_on date
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare
  v_rows jsonb;
  v_revenue numeric:=0;
  v_expense numeric:=0;
begin
  if not atlas.accounting_book_authorized_self_v1(p_accounting_book_id) then
    raise exception 'Accounting book authority required.' using errcode='42501';
  end if;
  if p_start_on is null or p_end_on is null or p_end_on<p_start_on then
    raise exception 'Valid Profit and Loss date range required.' using errcode='22023';
  end if;

  with activity as (
    select account.id,account.account_key,account.account_code,account.account_name,account.account_class,
      coalesce(sum(line.debit_amount),0) as debit_total,
      coalesce(sum(line.credit_amount),0) as credit_total
    from atlas.accounting_accounts account
    left join atlas.accounting_journal_lines line on line.accounting_account_id=account.id
    left join atlas.accounting_journal_entries entry
      on entry.id=line.journal_entry_id
     and entry.entry_state='posted'
     and entry.entry_date between p_start_on and p_end_on
    where account.accounting_book_id=p_accounting_book_id
      and account.account_class in ('revenue','expense')
    group by account.id,account.account_key,account.account_code,account.account_name,account.account_class
  ), normalized as (
    select *,case when account_class='revenue' then credit_total-debit_total else debit_total-credit_total end as report_amount
    from activity
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'accountingAccountId',id,'accountKey',account_key,'accountCode',account_code,
    'accountName',account_name,'accountClass',account_class,
    'debitActivity',debit_total,'creditActivity',credit_total,'amount',report_amount
  ) order by account_class desc,account_code nulls last,account_name,id),'[]'::jsonb),
  coalesce(sum(report_amount) filter(where account_class='revenue'),0),
  coalesce(sum(report_amount) filter(where account_class='expense'),0)
  into v_rows,v_revenue,v_expense
  from normalized;

  return jsonb_build_object(
    'contractVersion','accounting_profit_and_loss_v1',
    'accountingBookId',p_accounting_book_id,'startOn',p_start_on,'endOn',p_end_on,
    'revenue',v_revenue,'expense',v_expense,'netIncome',v_revenue-v_expense,
    'accounts',v_rows,
    'truthBoundary',jsonb_build_object('postedEntriesOnly',true,'readOnly',true,'accountingProjectionOnly',true)
  );
end;
$$;

revoke all on function atlas.accounting_profit_and_loss_self_api_v1(uuid,date,date) from public,anon;
grant execute on function atlas.accounting_profit_and_loss_self_api_v1(uuid,date,date) to authenticated;

create or replace function atlas.accounting_balance_sheet_self_api_v1(
  p_accounting_book_id uuid,
  p_as_of_on date
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare
  v_rows jsonb;
  v_assets numeric:=0;
  v_liabilities numeric:=0;
  v_equity numeric:=0;
  v_revenue numeric:=0;
  v_expense numeric:=0;
  v_current_earnings numeric:=0;
  v_right_side numeric:=0;
begin
  if not atlas.accounting_book_authorized_self_v1(p_accounting_book_id) then
    raise exception 'Accounting book authority required.' using errcode='42501';
  end if;
  if p_as_of_on is null then raise exception 'Balance Sheet as-of date required.' using errcode='22023'; end if;

  with activity as (
    select account.id,account.account_key,account.account_code,account.account_name,account.account_class,
      coalesce(sum(case when entry.id is not null then line.debit_amount else 0 end),0) as debit_total,
      coalesce(sum(case when entry.id is not null then line.credit_amount else 0 end),0) as credit_total
    from atlas.accounting_accounts account
    left join atlas.accounting_journal_lines line on line.accounting_account_id=account.id
    left join atlas.accounting_journal_entries entry
      on entry.id=line.journal_entry_id and entry.entry_state='posted' and entry.entry_date<=p_as_of_on
    where account.accounting_book_id=p_accounting_book_id
    group by account.id,account.account_key,account.account_code,account.account_name,account.account_class
  ), normalized as (
    select *,case
      when account_class in ('asset','expense') then debit_total-credit_total
      else credit_total-debit_total
    end as report_amount
    from activity
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'accountingAccountId',id,'accountKey',account_key,'accountCode',account_code,
    'accountName',account_name,'accountClass',account_class,
    'debitActivity',debit_total,'creditActivity',credit_total,'amount',report_amount
  ) order by account_class,account_code nulls last,account_name,id),'[]'::jsonb),
  coalesce(sum(report_amount) filter(where account_class='asset'),0),
  coalesce(sum(report_amount) filter(where account_class='liability'),0),
  coalesce(sum(report_amount) filter(where account_class='equity'),0),
  coalesce(sum(report_amount) filter(where account_class='revenue'),0),
  coalesce(sum(report_amount) filter(where account_class='expense'),0)
  into v_rows,v_assets,v_liabilities,v_equity,v_revenue,v_expense
  from normalized;

  v_current_earnings:=v_revenue-v_expense;
  v_right_side:=v_liabilities+v_equity+v_current_earnings;

  return jsonb_build_object(
    'contractVersion','accounting_balance_sheet_v1',
    'accountingBookId',p_accounting_book_id,'asOfOn',p_as_of_on,
    'assets',v_assets,'liabilities',v_liabilities,'equityBeforeCurrentEarnings',v_equity,
    'currentEarnings',v_current_earnings,'liabilitiesAndEquity',v_right_side,
    'balanced',v_assets=v_right_side,
    'accounts',v_rows,
    'truthBoundary',jsonb_build_object(
      'postedEntriesOnly',true,'readOnly',true,'currentEarningsComputedFromUnclosedRevenueAndExpense',true,
      'accountingProjectionOnly',true
    )
  );
end;
$$;

revoke all on function atlas.accounting_balance_sheet_self_api_v1(uuid,date) from public,anon;
grant execute on function atlas.accounting_balance_sheet_self_api_v1(uuid,date) to authenticated;

comment on function atlas.accounting_profit_and_loss_self_api_v1(uuid,date,date) is
  'Posted-entry Profit and Loss projection for one accounting book and date range.';
comment on function atlas.accounting_balance_sheet_self_api_v1(uuid,date) is
  'Posted-entry Balance Sheet projection. Current earnings are computed from cumulative revenue less expense until explicit closing entries are introduced.';
