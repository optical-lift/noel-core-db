begin;

do $$
declare v_def text;
begin
  if to_regprocedure('atlas.accounting_profit_and_loss_self_api_v1(uuid,date,date)') is null then
    raise exception 'Profit and Loss accounting projection missing';
  end if;
  if to_regprocedure('atlas.accounting_balance_sheet_self_api_v1(uuid,date)') is null then
    raise exception 'Balance Sheet accounting projection missing';
  end if;
  if not has_function_privilege('authenticated','atlas.accounting_profit_and_loss_self_api_v1(uuid,date,date)','EXECUTE')
     or not has_function_privilege('authenticated','atlas.accounting_balance_sheet_self_api_v1(uuid,date)','EXECUTE') then
    raise exception 'Accounting financial statement reads must be available to authenticated authorized callers';
  end if;

  select pg_get_functiondef('atlas.accounting_profit_and_loss_self_api_v1(uuid,date,date)'::regprocedure) into v_def;
  if position('entry_state=''posted''' in replace(v_def,' ',''))=0
     or position('netIncome' in v_def)=0 then
    raise exception 'Profit and Loss must be posted-entry only and compute net income';
  end if;

  select pg_get_functiondef('atlas.accounting_balance_sheet_self_api_v1(uuid,date)'::regprocedure) into v_def;
  if position('entry_state=''posted''' in replace(v_def,' ',''))=0
     or position('currentEarnings' in v_def)=0
     or position('liabilitiesAndEquity' in v_def)=0 then
    raise exception 'Balance Sheet must be posted-entry only and include current earnings in the accounting equation';
  end if;
end;
$$;

rollback;
