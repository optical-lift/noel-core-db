-- Freeze historical meaning of governed resource pools once used.

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
  v_has_posted_activity boolean:=false;
begin
  if tg_op='UPDATE' then
    if old.accounting_book_id is distinct from new.accounting_book_id
       or old.pool_key is distinct from new.pool_key
       or old.ownership_posture is distinct from new.ownership_posture
       or old.governance_posture is distinct from new.governance_posture
       or old.custody_asset_account_id is distinct from new.custody_asset_account_id
       or old.custody_liability_account_id is distinct from new.custody_liability_account_id then
      raise exception 'Resource pool book/key/ownership/governance/control-account identity is immutable.' using errcode='23514';
    end if;

    select exists(
      select 1
      from atlas.accounting_resource_movements m
      join atlas.accounting_journal_lines l on l.id=m.journal_line_id
      join atlas.accounting_journal_entries e on e.id=l.journal_entry_id
      where m.resource_pool_id=old.id and e.entry_state='posted'
    ) into v_has_posted_activity;

    if v_has_posted_activity and old.nonprofit_net_asset_class is distinct from new.nonprofit_net_asset_class then
      raise exception 'Nonprofit net-asset classification is historically frozen after posted resource activity.' using errcode='55000';
    end if;
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
