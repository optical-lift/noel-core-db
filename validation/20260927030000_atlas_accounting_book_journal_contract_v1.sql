begin;

do $$
declare
  v_table text;
  v_function text;
  v_def text;
  v_rls boolean;
begin
  foreach v_table in array array[
    'atlas.accounting_books',
    'atlas.accounting_book_ledger_scopes',
    'atlas.accounting_accounts',
    'atlas.accounting_periods',
    'atlas.accounting_journal_entries',
    'atlas.accounting_journal_lines',
    'atlas.accounting_journal_entry_sources',
    'atlas.accounting_financial_source_account_bindings'
  ] loop
    if to_regclass(v_table) is null then raise exception 'missing accounting relation: %',v_table; end if;
    select c.relrowsecurity into v_rls from pg_class c where c.oid=to_regclass(v_table);
    if not coalesce(v_rls,false) then raise exception 'accounting relation must have RLS enabled: %',v_table; end if;
    if has_table_privilege('authenticated',v_table,'INSERT')
       or has_table_privilege('authenticated',v_table,'UPDATE')
       or has_table_privilege('authenticated',v_table,'DELETE') then
      raise exception 'authenticated must not write accounting relation directly: %',v_table;
    end if;
  end loop;

  foreach v_function in array array[
    'atlas.create_accounting_book_self_api_v1(uuid,text,text,text,text,integer,uuid[],jsonb,jsonb)',
    'atlas.upsert_accounting_account_self_api_v1(uuid,text,text,text,text,text,text,uuid,jsonb)',
    'atlas.open_accounting_period_self_api_v1(uuid,text,date,date,jsonb)',
    'atlas.replace_accounting_journal_draft_self_api_v1(uuid,text,date,text,text,jsonb,jsonb,jsonb,uuid)',
    'atlas.post_accounting_journal_entry_self_api_v1(uuid)',
    'atlas.reverse_accounting_journal_entry_self_api_v1(uuid,date,text,text)',
    'atlas.close_accounting_period_self_api_v1(uuid)',
    'atlas.reopen_accounting_period_self_api_v1(uuid)',
    'atlas.lock_accounting_period_self_api_v1(uuid)',
    'atlas.accounting_book_self_api_v1(uuid)',
    'atlas.accounting_trial_balance_self_api_v1(uuid,date)',
    'atlas.accounting_journal_window_self_api_v1(uuid,date,date)',
    'atlas.bind_accounting_financial_source_account_self_api_v1(uuid,uuid,uuid,text,jsonb,jsonb)',
    'atlas.propose_accounting_entry_from_financial_review_self_api_v2(uuid,uuid,jsonb,text,jsonb)'
  ] loop
    if to_regprocedure(v_function) is null then raise exception 'missing accounting function: %',v_function; end if;
  end loop;

  if not exists(select 1 from pg_trigger where tgrelid='atlas.accounting_journal_entries'::regclass and tgname='accounting_journal_entries_mutation_guard_v1' and tgenabled<>'D') then
    raise exception 'journal entry immutability trigger missing';
  end if;
  if not exists(select 1 from pg_trigger where tgrelid='atlas.accounting_journal_entries'::regclass and tgname='accounting_journal_entries_open_period_guard_v1' and tgenabled<>'D') then
    raise exception 'journal open-period trigger missing';
  end if;
  if not exists(select 1 from pg_trigger where tgrelid='atlas.accounting_journal_lines'::regclass and tgname='accounting_journal_lines_guard_v1' and tgenabled<>'D') then
    raise exception 'journal line guard missing';
  end if;
  if not exists(select 1 from pg_trigger where tgrelid='atlas.accounting_periods'::regclass and tgname='accounting_periods_guard_v1' and tgenabled<>'D') then
    raise exception 'accounting period overlap guard missing';
  end if;

  select pg_get_functiondef('atlas.post_accounting_journal_entry_self_api_v1(uuid)'::regprocedure) into v_def;
  if position('period_state<>''open''' in replace(v_def,' ',''))=0
     or position('accounting_entry_balance_core_v1' in v_def)=0 then
    raise exception 'posting must require an open period and balanced entry';
  end if;

  select pg_get_functiondef('atlas.reverse_accounting_journal_entry_self_api_v1(uuid,date,text,text)'::regprocedure) into v_def;
  if position('reversal_of_entry_id' in lower(v_def))=0
     or position('post_accounting_journal_entry_self_api_v1' in v_def)=0 then
    raise exception 'reversal must create and post a linked reversing entry';
  end if;

  select pg_get_functiondef('atlas.propose_accounting_entry_from_financial_review_self_api_v1(uuid,uuid,jsonb,text,jsonb)'::regprocedure) into v_def;
  if position('post_accounting_journal_entry_self_api_v1' in v_def)>0 then
    raise exception 'financial review proposal must never post accounting automatically';
  end if;
  if position('operating_expense' in v_def)=0 or position('operating_revenue' in v_def)=0 or position('owner_funding' in v_def)=0 then
    raise exception 'financial proposal supported-treatment contract missing';
  end if;

  if has_function_privilege('authenticated','atlas.propose_accounting_entry_from_financial_review_self_api_v1(uuid,uuid,jsonb,text,jsonb)','EXECUTE') then
    raise exception 'authenticated callers must use hardened financial proposal v2';
  end if;
  if not has_function_privilege('authenticated','atlas.propose_accounting_entry_from_financial_review_self_api_v2(uuid,uuid,jsonb,text,jsonb)','EXECUTE') then
    raise exception 'hardened financial proposal v2 must be callable by authenticated users';
  end if;

  select pg_get_functiondef('atlas.guard_accounting_book_history_v1()'::regprocedure) into v_def;
  if position('posted' in lower(v_def))=0 or position('base_currency' in lower(v_def))=0 or position('accounting_basis' in lower(v_def))=0 then
    raise exception 'book history guard must freeze currency/basis after posting';
  end if;

  select pg_get_functiondef('atlas.guard_accounting_account_history_v1()'::regprocedure) into v_def;
  if position('account_class' in lower(v_def))=0 or position('normal_balance' in lower(v_def))=0 then
    raise exception 'account history guard must freeze class/normal balance after posting';
  end if;
end;
$$;

rollback;
