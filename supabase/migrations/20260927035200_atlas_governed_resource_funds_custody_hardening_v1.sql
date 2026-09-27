-- Hardening for governed resource funds / third-party custody.

create unique index if not exists accounting_resource_pools_custody_liability_uq
  on atlas.accounting_resource_pools(accounting_book_id,custody_liability_account_id)
  where ownership_posture='third_party_custody' and pool_state='active';

create unique index if not exists accounting_resource_pools_custody_asset_uq
  on atlas.accounting_resource_pools(accounting_book_id,custody_asset_account_id)
  where ownership_posture='third_party_custody' and pool_state='active';

create or replace function atlas.guard_accounting_resource_movement_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_entry_state text;
  v_line_book uuid;
  v_line_account uuid;
  v_debit numeric;
  v_credit numeric;
  v_pool_book uuid;
  v_ownership text;
  v_liability_account uuid;
  v_interest_pool uuid;
  v_existing_abs numeric;
begin
  if tg_op='DELETE' then
    select e.entry_state into v_entry_state
    from atlas.accounting_journal_lines l join atlas.accounting_journal_entries e on e.id=l.journal_entry_id
    where l.id=old.journal_line_id;
    if v_entry_state<>'draft' then raise exception 'Posted resource movements are immutable.' using errcode='55000'; end if;
    return old;
  end if;

  select e.entry_state,e.accounting_book_id,l.accounting_account_id,l.debit_amount,l.credit_amount
  into v_entry_state,v_line_book,v_line_account,v_debit,v_credit
  from atlas.accounting_journal_lines l
  join atlas.accounting_journal_entries e on e.id=l.journal_entry_id
  where l.id=new.journal_line_id;
  if v_line_book is null then raise exception 'Journal line not found.' using errcode='23503'; end if;
  if v_entry_state<>'draft' then raise exception 'Resource movements may only be edited while the journal entry is draft.' using errcode='55000'; end if;

  select accounting_book_id,ownership_posture,custody_liability_account_id
  into v_pool_book,v_ownership,v_liability_account
  from atlas.accounting_resource_pools where id=new.resource_pool_id and pool_state='active';
  if v_pool_book is null or v_pool_book<>v_line_book then
    raise exception 'Resource movement pool must be active in the same accounting book.' using errcode='23514';
  end if;

  if new.resource_interest_id is not null then
    select resource_pool_id into v_interest_pool from atlas.accounting_resource_interests
    where id=new.resource_interest_id and interest_state='active';
    if v_interest_pool is null or v_interest_pool<>new.resource_pool_id then
      raise exception 'Resource movement interest must be active in the same resource pool.' using errcode='23514';
    end if;
  end if;

  if v_ownership='third_party_custody' then
    if new.resource_interest_id is null then
      raise exception 'Custodial resource movements require a canonical beneficiary/client interest.' using errcode='23514';
    end if;
    if v_line_account<>v_liability_account then
      raise exception 'Custodial resource movement must attach to the pool liability-control journal line.' using errcode='23514';
    end if;
    if v_credit>0 then
      if new.amount_delta<=0 or new.movement_kind<>'custody_increase' then
        raise exception 'Credit to custodial liability requires a positive custody_increase.' using errcode='23514';
      end if;
    elsif v_debit>0 then
      if new.amount_delta>=0 or new.movement_kind<>'custody_decrease' then
        raise exception 'Debit to custodial liability requires a negative custody_decrease.' using errcode='23514';
      end if;
    end if;
    if abs(new.amount_delta)>greatest(v_debit,v_credit) then
      raise exception 'Custodial subledger effect may not exceed its liability journal line.' using errcode='23514';
    end if;
  end if;

  select coalesce(sum(abs(m.amount_delta)),0)
  into v_existing_abs
  from atlas.accounting_resource_movements m
  where m.journal_line_id=new.journal_line_id
    and m.id<>new.id;
  if v_existing_abs+abs(new.amount_delta)>greatest(v_debit,v_credit) then
    raise exception 'Resource allocations on a journal line may not exceed the journal-line amount.' using errcode='23514';
  end if;
  return new;
end;
$$;

create or replace function atlas.guard_accounting_resource_posting_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_bad record;
begin
  if not (old.entry_state='draft' and new.entry_state='posted') then return new; end if;

  -- Every liability line belonging to a custodial pool must be fully assigned to beneficiary/client interests.
  select l.id as journal_line_id,p.id as resource_pool_id,
         greatest(l.debit_amount,l.credit_amount) as line_amount,
         coalesce(sum(abs(m.amount_delta)),0) as allocated_amount
  into v_bad
  from atlas.accounting_journal_lines l
  join atlas.accounting_resource_pools p
    on p.accounting_book_id=new.accounting_book_id
   and p.ownership_posture='third_party_custody'
   and p.pool_state='active'
   and p.custody_liability_account_id=l.accounting_account_id
  left join atlas.accounting_resource_movements m
    on m.journal_line_id=l.id and m.resource_pool_id=p.id
  where l.journal_entry_id=new.id
  group by l.id,p.id,l.debit_amount,l.credit_amount
  having coalesce(sum(abs(m.amount_delta)),0)<>greatest(l.debit_amount,l.credit_amount)
  limit 1;
  if v_bad.journal_line_id is not null then
    raise exception 'Every custodial liability journal line must be fully allocated to beneficiary/client subledgers before posting.' using errcode='23514';
  end if;

  -- A custodial client/beneficiary may never consume another beneficiary's money.
  v_bad:=null;
  select x.resource_interest_id,x.balance_after
  into v_bad
  from (
    select m.resource_interest_id,
      coalesce((
        select sum(pm.amount_delta)
        from atlas.accounting_resource_movements pm
        join atlas.accounting_journal_lines pl on pl.id=pm.journal_line_id
        join atlas.accounting_journal_entries pe on pe.id=pl.journal_entry_id
        where pm.resource_interest_id=m.resource_interest_id and pe.entry_state='posted'
      ),0)
      + sum(m.amount_delta) as balance_after
    from atlas.accounting_resource_movements m
    join atlas.accounting_journal_lines l on l.id=m.journal_line_id
    join atlas.accounting_resource_pools p on p.id=m.resource_pool_id
    where l.journal_entry_id=new.id
      and p.ownership_posture='third_party_custody'
    group by m.resource_interest_id
  ) x
  where x.balance_after<0
  limit 1;
  if v_bad.resource_interest_id is not null then
    raise exception 'Posting would make a custodial beneficiary/client balance negative.' using errcode='23514';
  end if;

  -- If a pool has explicit eligible Ledger scopes, a decrease must be assigned to one of them.
  if exists(
    select 1
    from atlas.accounting_resource_movements m
    join atlas.accounting_journal_lines l on l.id=m.journal_line_id
    where l.journal_entry_id=new.id
      and m.amount_delta<0
      and exists(
        select 1 from atlas.accounting_resource_pool_ledger_scopes s
        where s.resource_pool_id=m.resource_pool_id and s.scope_state='active' and s.ended_at is null
      )
      and not exists(
        select 1 from atlas.accounting_resource_pool_ledger_scopes s
        where s.resource_pool_id=m.resource_pool_id and s.scope_state='active' and s.ended_at is null
          and s.ledger_id=l.ledger_id
      )
  ) then
    raise exception 'Resource decrease is outside the pool permitted Ledger scope.' using errcode='23514';
  end if;

  return new;
end;
$$;

-- Third-party custodial pools can never carry nonprofit net-asset classifications.
create or replace function atlas.guard_accounting_resource_pool_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_asset_book uuid;
  v_asset_class text;
  v_liability_book uuid;
  v_liability_class text;
begin
  if tg_op='UPDATE' and old.accounting_book_id is distinct from new.accounting_book_id then
    raise exception 'Resource pool accounting book is immutable.' using errcode='23514';
  end if;
  if new.ownership_posture='third_party_custody' and new.nonprofit_net_asset_class is not null then
    raise exception 'Third-party custodial resources are liabilities, not nonprofit net assets.' using errcode='23514';
  end if;
  if new.governance_posture='internally_designated' and new.nonprofit_net_asset_class='with_donor_restrictions' then
    raise exception 'Internal board/management designation is not a donor restriction.' using errcode='23514';
  end if;

  if new.ownership_posture='third_party_custody' then
    select accounting_book_id,account_class into v_asset_book,v_asset_class
    from atlas.accounting_accounts where id=new.custody_asset_account_id and account_state='active';
    select accounting_book_id,account_class into v_liability_book,v_liability_class
    from atlas.accounting_accounts where id=new.custody_liability_account_id and account_state='active';
    if v_asset_book is null or v_liability_book is null
       or v_asset_book<>new.accounting_book_id or v_liability_book<>new.accounting_book_id
       or v_asset_class<>'asset' or v_liability_class<>'liability' then
      raise exception 'Custodial pools require active same-book asset and liability control accounts.' using errcode='23514';
    end if;
  end if;
  new.updated_at:=now();
  return new;
end;
$$;
