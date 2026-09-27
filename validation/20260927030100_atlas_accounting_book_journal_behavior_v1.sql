begin;

do $$
declare
  v_entity_id uuid:=gen_random_uuid();
  v_book_id uuid:=gen_random_uuid();
  v_cash_id uuid:=gen_random_uuid();
  v_expense_id uuid:=gen_random_uuid();
  v_parent_id uuid:=gen_random_uuid();
  v_child_id uuid:=gen_random_uuid();
  v_period_id uuid:=gen_random_uuid();
  v_entry_id uuid:=gen_random_uuid();
  v_balance jsonb;
  v_failed boolean:=false;
begin
  insert into reality.entities(id,stable_key,entity_kind,display_name,identity_state,metadata)
  values(v_entity_id,'validation:accounting:'||v_entity_id::text,'business','Accounting Validation Entity','canonical','{}'::jsonb);

  insert into atlas.accounting_books(
    id,reporting_entity_id,stable_key,book_name,base_currency,accounting_basis,fiscal_year_start_month,provenance,metadata
  ) values(
    v_book_id,v_entity_id,'validation','Validation Book','USD','cash',1,'{}'::jsonb,'{}'::jsonb
  );

  insert into atlas.accounting_accounts(
    id,accounting_book_id,account_key,account_name,account_class,normal_balance,provenance,metadata
  ) values
    (v_cash_id,v_book_id,'cash','Cash','asset','debit','{}'::jsonb,'{}'::jsonb),
    (v_expense_id,v_book_id,'expense','Expense','expense','debit','{}'::jsonb,'{}'::jsonb),
    (v_parent_id,v_book_id,'parent','Parent','expense','debit','{}'::jsonb,'{}'::jsonb),
    (v_child_id,v_book_id,'child','Child','expense','debit','{}'::jsonb,'{}'::jsonb);

  update atlas.accounting_accounts set parent_account_id=v_parent_id where id=v_child_id;
  begin
    update atlas.accounting_accounts set parent_account_id=v_child_id where id=v_parent_id;
    raise exception 'expected accounting hierarchy cycle rejection';
  exception when check_violation then
    null;
  end;

  insert into atlas.accounting_periods(
    id,accounting_book_id,period_key,period_start_on,period_end_on,period_state,provenance,metadata
  ) values(
    v_period_id,v_book_id,'2025',date '2025-01-01',date '2025-12-31','open','{}'::jsonb,'{}'::jsonb
  );

  begin
    insert into atlas.accounting_periods(
      accounting_book_id,period_key,period_start_on,period_end_on,period_state,provenance,metadata
    ) values(
      v_book_id,'overlap',date '2025-06-01',date '2026-05-31','open','{}'::jsonb,'{}'::jsonb
    );
    raise exception 'expected accounting period overlap rejection';
  exception when check_violation then
    null;
  end;

  insert into atlas.accounting_journal_entries(
    id,accounting_book_id,client_entry_key,entry_date,entry_kind,entry_state,memo,input_sha256,provenance,metadata
  ) values(
    v_entry_id,v_book_id,'validation-entry',date '2025-01-15','standard','draft','Validation entry',repeat('a',64),'{}'::jsonb,'{}'::jsonb
  );

  insert into atlas.accounting_journal_lines(
    journal_entry_id,line_ordinal,accounting_account_id,debit_amount,credit_amount,dimensions,metadata
  ) values
    (v_entry_id,1,v_expense_id,25,0,'{}'::jsonb,'{}'::jsonb),
    (v_entry_id,2,v_cash_id,0,25,'{}'::jsonb,'{}'::jsonb);

  v_balance:=atlas.accounting_entry_balance_core_v1(v_entry_id);
  if coalesce((v_balance->>'balanced')::boolean,false) is not true
     or (v_balance->>'debitTotal')::numeric<>25
     or (v_balance->>'creditTotal')::numeric<>25 then
    raise exception 'balanced accounting entry core check failed: %',v_balance;
  end if;

  -- Exercise DELETE semantics on the draft-line guard, then restore the balanced line.
  delete from atlas.accounting_journal_lines where journal_entry_id=v_entry_id and line_ordinal=2;
  insert into atlas.accounting_journal_lines(
    journal_entry_id,line_ordinal,accounting_account_id,debit_amount,credit_amount,dimensions,metadata
  ) values(v_entry_id,2,v_cash_id,0,25,'{}'::jsonb,'{}'::jsonb);

  update atlas.accounting_journal_entries
  set entry_state='cancelled',cancelled_at=now()
  where id=v_entry_id;

  begin
    update atlas.accounting_journal_entries set memo='mutated after cancel' where id=v_entry_id;
    raise exception 'expected cancelled-entry immutability rejection';
  exception when sqlstate '55000' then
    null;
  end;

  begin
    delete from atlas.accounting_journal_lines where journal_entry_id=v_entry_id and line_ordinal=1;
    raise exception 'expected cancelled-entry line immutability rejection';
  exception when sqlstate '55000' then
    null;
  end;
end;
$$;

rollback;
