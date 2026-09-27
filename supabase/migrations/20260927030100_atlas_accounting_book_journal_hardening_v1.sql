-- Accounting book/journal hardening v1.
-- Preserve historical reporting semantics and prevent closed-period shadow drafts.

alter table atlas.accounting_book_ledger_scopes
  add column if not exists updated_at timestamptz not null default now();

create or replace function atlas.guard_accounting_book_history_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $$
begin
  if old.id<>new.id or old.reporting_entity_id<>new.reporting_entity_id or old.stable_key<>new.stable_key then
    raise exception 'Accounting book identity is immutable.' using errcode='23514';
  end if;
  if (old.base_currency is distinct from new.base_currency or old.accounting_basis is distinct from new.accounting_basis)
     and exists(
       select 1 from atlas.accounting_journal_entries e
       where e.accounting_book_id=old.id and e.entry_state='posted'
     ) then
    raise exception 'Base currency and accounting basis cannot change after the book has posted history.' using errcode='55000';
  end if;
  new.updated_at:=now();
  return new;
end;
$$;

revoke all on function atlas.guard_accounting_book_history_v1() from public,anon,authenticated;
drop trigger if exists accounting_books_history_guard_v1 on atlas.accounting_books;
create trigger accounting_books_history_guard_v1
before update on atlas.accounting_books
for each row execute function atlas.guard_accounting_book_history_v1();

create or replace function atlas.guard_accounting_account_history_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $$
begin
  if old.id<>new.id or old.accounting_book_id<>new.accounting_book_id or old.account_key<>new.account_key then
    raise exception 'Accounting account identity is immutable.' using errcode='23514';
  end if;
  if (old.account_class is distinct from new.account_class or old.normal_balance is distinct from new.normal_balance)
     and exists(
       select 1
       from atlas.accounting_journal_lines line
       join atlas.accounting_journal_entries entry on entry.id=line.journal_entry_id
       where line.accounting_account_id=old.id and entry.entry_state='posted'
     ) then
    raise exception 'Account class and normal balance cannot change after posted use.' using errcode='55000';
  end if;
  new.updated_at:=now();
  return new;
end;
$$;

revoke all on function atlas.guard_accounting_account_history_v1() from public,anon,authenticated;
drop trigger if exists accounting_accounts_history_guard_v1 on atlas.accounting_accounts;
create trigger accounting_accounts_history_guard_v1
before update on atlas.accounting_accounts
for each row execute function atlas.guard_accounting_account_history_v1();

create or replace function atlas.guard_accounting_journal_entry_open_period_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $$
begin
  if new.entry_state='draft' and not exists(
    select 1 from atlas.accounting_periods period
    where period.accounting_book_id=new.accounting_book_id
      and new.entry_date between period.period_start_on and period.period_end_on
      and period.period_state='open'
  ) then
    raise exception 'A draft accounting entry requires an open accounting period covering its entry date.' using errcode='55000';
  end if;
  return new;
end;
$$;

revoke all on function atlas.guard_accounting_journal_entry_open_period_v1() from public,anon,authenticated;
drop trigger if exists accounting_journal_entries_open_period_guard_v1 on atlas.accounting_journal_entries;
create trigger accounting_journal_entries_open_period_guard_v1
before insert or update of accounting_book_id,entry_date
on atlas.accounting_journal_entries
for each row execute function atlas.guard_accounting_journal_entry_open_period_v1();

create or replace function atlas.accounting_book_self_api_v1(p_accounting_book_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth,reality,ledger
as $$
declare v_book atlas.accounting_books%rowtype;
begin
  if not atlas.accounting_book_authorized_self_v1(p_accounting_book_id) then raise exception 'Accounting book authority required.' using errcode='42501'; end if;
  select * into v_book from atlas.accounting_books where id=p_accounting_book_id;
  return jsonb_build_object(
    'contractVersion','accounting_book_read_v1',
    'book',jsonb_build_object(
      'accountingBookId',v_book.id,'reportingEntityId',v_book.reporting_entity_id,'stableKey',v_book.stable_key,
      'bookName',v_book.book_name,'baseCurrency',v_book.base_currency,'accountingBasis',v_book.accounting_basis,
      'fiscalYearStartMonth',v_book.fiscal_year_start_month,'bookState',v_book.book_state
    ),
    'ledgerScopes',coalesce((select jsonb_agg(jsonb_build_object(
      'ledgerId',scope.ledger_id,'ledgerName',l.name,'subjectEntityId',l.subject_entity_id,'scopeState',scope.scope_state
    ) order by l.name,scope.ledger_id)
      from atlas.accounting_book_ledger_scopes scope join ledger.ledgers l on l.id=scope.ledger_id
      where scope.accounting_book_id=v_book.id),'[]'::jsonb),
    'accounts',coalesce((select jsonb_agg(jsonb_build_object(
      'accountingAccountId',a.id,'accountKey',a.account_key,'accountCode',a.account_code,'accountName',a.account_name,
      'accountClass',a.account_class,'accountSubtype',a.account_subtype,'parentAccountId',a.parent_account_id,
      'normalBalance',a.normal_balance,'accountState',a.account_state
    ) order by a.account_code nulls last,a.account_name,a.id)
      from atlas.accounting_accounts a where a.accounting_book_id=v_book.id),'[]'::jsonb),
    'periods',coalesce((select jsonb_agg(jsonb_build_object(
      'accountingPeriodId',p.id,'periodKey',p.period_key,'periodStartOn',p.period_start_on,'periodEndOn',p.period_end_on,
      'periodState',p.period_state,'closedAt',p.closed_at,'lockedAt',p.locked_at
    ) order by p.period_start_on,p.id)
      from atlas.accounting_periods p where p.accounting_book_id=v_book.id),'[]'::jsonb),
    'truthBoundary',jsonb_build_object('readOnly',true,'postedEntriesImmutable',true,'accountingDoesNotRewriteSourceTruth',true)
  );
end;
$$;

create or replace function atlas.accounting_trial_balance_self_api_v1(
  p_accounting_book_id uuid,
  p_as_of_on date
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare v_total_debits numeric; v_total_credits numeric; v_items jsonb;
begin
  if not atlas.accounting_book_authorized_self_v1(p_accounting_book_id) then raise exception 'Accounting book authority required.' using errcode='42501'; end if;
  if p_as_of_on is null then raise exception 'Trial-balance as-of date required.' using errcode='22023'; end if;

  with balances as (
    select a.id,a.account_key,a.account_code,a.account_name,a.account_class,a.normal_balance,
           coalesce(sum(case when e.id is not null then line.debit_amount else 0 end),0) as debit_total,
           coalesce(sum(case when e.id is not null then line.credit_amount else 0 end),0) as credit_total
    from atlas.accounting_accounts a
    left join atlas.accounting_journal_lines line on line.accounting_account_id=a.id
    left join atlas.accounting_journal_entries e
      on e.id=line.journal_entry_id and e.entry_state='posted' and e.entry_date<=p_as_of_on
    where a.accounting_book_id=p_accounting_book_id
    group by a.id,a.account_key,a.account_code,a.account_name,a.account_class,a.normal_balance
  ), normalized as (
    select *,greatest(debit_total-credit_total,0) as ending_debit,
             greatest(credit_total-debit_total,0) as ending_credit
    from balances
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'accountingAccountId',id,'accountKey',account_key,'accountCode',account_code,'accountName',account_name,
    'accountClass',account_class,'normalBalance',normal_balance,
    'debitActivity',debit_total,'creditActivity',credit_total,'endingDebit',ending_debit,'endingCredit',ending_credit
  ) order by account_code nulls last,account_name,id),'[]'::jsonb),
  coalesce(sum(debit_total),0),coalesce(sum(credit_total),0)
  into v_items,v_total_debits,v_total_credits
  from normalized;

  return jsonb_build_object(
    'contractVersion','accounting_trial_balance_v1','accountingBookId',p_accounting_book_id,'asOfOn',p_as_of_on,
    'debitTotal',v_total_debits,'creditTotal',v_total_credits,'balanced',v_total_debits=v_total_credits,
    'accounts',v_items,'truthBoundary',jsonb_build_object('postedEntriesOnly',true,'readOnly',true)
  );
end;
$$;

comment on function atlas.guard_accounting_book_history_v1() is
  'Prevents reporting currency/basis changes after posted accounting history exists.';
comment on function atlas.guard_accounting_account_history_v1() is
  'Prevents account class/normal-balance retyping after posted use.';
comment on function atlas.guard_accounting_journal_entry_open_period_v1() is
  'Requires an open accounting period before a new or redated draft can exist.';
