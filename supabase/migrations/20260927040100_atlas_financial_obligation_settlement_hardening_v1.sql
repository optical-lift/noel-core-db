-- Atlas financial obligation + settlement hardening v1.
-- Conditionality, economic earning, and refundability are independent dimensions.

alter table atlas.financial_obligations
  add column if not exists condition_state text not null default 'not_applicable';

alter table atlas.financial_obligations
  drop constraint if exists financial_obligations_entitlement_state_check;
alter table atlas.financial_obligations
  add constraint financial_obligations_entitlement_state_check check (
    entitlement_state in ('not_applicable','unearned','earned')
  );

alter table atlas.financial_obligations
  add constraint financial_obligations_condition_state_check check (
    condition_state in ('not_applicable','conditional','satisfied','released','failed')
  );

create or replace function atlas.guard_financial_obligation_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if tg_op='DELETE' then
    raise exception 'Financial obligations are retained economic history; void them through the governed state path.' using errcode='55000';
  end if;

  if old.accounting_book_id is distinct from new.accounting_book_id
     or old.obligation_key is distinct from new.obligation_key
     or old.obligation_kind is distinct from new.obligation_kind
     or old.face_amount is distinct from new.face_amount
     or old.currency is distinct from new.currency
     or old.incurred_on is distinct from new.incurred_on
     or old.due_on is distinct from new.due_on
     or old.evidence_record_id is distinct from new.evidence_record_id
     or old.created_by_principal_id is distinct from new.created_by_principal_id then
    raise exception 'Core financial obligation identity and terms are immutable; corrections require a new obligation/event.' using errcode='55000';
  end if;

  if old.settlement_state in ('forgiven','written_off','voided')
     and old.settlement_state is distinct from new.settlement_state then
    raise exception 'Terminal financial obligation state cannot be revived.' using errcode='55000';
  end if;

  new.updated_at:=now();
  return new;
end;
$$;
revoke all on function atlas.guard_financial_obligation_mutation_v1() from public,anon,authenticated;
drop trigger if exists financial_obligations_mutation_guard_v1 on atlas.financial_obligations;
create trigger financial_obligations_mutation_guard_v1
before update or delete on atlas.financial_obligations
for each row execute function atlas.guard_financial_obligation_mutation_v1();

create or replace function atlas.guard_financial_obligation_party_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  raise exception 'Established financial obligation parties are append-only; correct the obligation rather than rewriting its parties.' using errcode='55000';
end;
$$;
revoke all on function atlas.guard_financial_obligation_party_mutation_v1() from public,anon,authenticated;
drop trigger if exists financial_obligation_parties_immutable_v1 on atlas.financial_obligation_parties;
create trigger financial_obligation_parties_immutable_v1
before update or delete on atlas.financial_obligation_parties
for each row execute function atlas.guard_financial_obligation_party_mutation_v1();

create or replace function atlas.guard_financial_settlement_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if tg_op='DELETE' then
    raise exception 'Financial settlements are retained history; void rather than delete.' using errcode='55000';
  end if;

  if old.accounting_book_id is distinct from new.accounting_book_id
     or old.settlement_key is distinct from new.settlement_key
     or old.settlement_on is distinct from new.settlement_on
     or old.settlement_kind is distinct from new.settlement_kind
     or old.amount is distinct from new.amount
     or old.currency is distinct from new.currency
     or old.medium_kind is distinct from new.medium_kind
     or old.evidence_record_id is distinct from new.evidence_record_id
     or old.created_by_principal_id is distinct from new.created_by_principal_id then
    raise exception 'Core financial settlement facts are immutable; corrections require lineage to a correcting settlement.' using errcode='55000';
  end if;

  if old.settlement_state='voided' and new.settlement_state<>'voided' then
    raise exception 'Voided financial settlement cannot be revived.' using errcode='55000';
  end if;
  if old.settlement_state='confirmed' and new.settlement_state='observed' then
    raise exception 'Confirmed financial settlement cannot return to observed state.' using errcode='55000';
  end if;

  new.updated_at:=now();
  return new;
end;
$$;
revoke all on function atlas.guard_financial_settlement_mutation_v1() from public,anon,authenticated;
drop trigger if exists financial_settlements_mutation_guard_v1 on atlas.financial_settlements;
create trigger financial_settlements_mutation_guard_v1
before update or delete on atlas.financial_settlements
for each row execute function atlas.guard_financial_settlement_mutation_v1();

create or replace function atlas.guard_financial_settlement_role_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  raise exception 'Established settlement roles are append-only; correct by settlement lineage.' using errcode='55000';
end;
$$;
revoke all on function atlas.guard_financial_settlement_role_mutation_v1() from public,anon,authenticated;
drop trigger if exists financial_settlement_roles_immutable_v1 on atlas.financial_settlement_roles;
create trigger financial_settlement_roles_immutable_v1
before update or delete on atlas.financial_settlement_roles
for each row execute function atlas.guard_financial_settlement_role_mutation_v1();

create or replace function atlas.guard_financial_settlement_allocation_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_settlement_book uuid;
  v_settlement_currency text;
  v_settlement_amount numeric;
  v_settlement_state text;
  v_obligation_book uuid;
  v_obligation_currency text;
  v_obligation_amount numeric;
  v_obligation_state text;
  v_settlement_used numeric;
  v_obligation_used numeric;
begin
  select accounting_book_id,currency,amount,settlement_state
    into v_settlement_book,v_settlement_currency,v_settlement_amount,v_settlement_state
  from atlas.financial_settlements where id=new.settlement_id;

  select accounting_book_id,currency,face_amount,settlement_state
    into v_obligation_book,v_obligation_currency,v_obligation_amount,v_obligation_state
  from atlas.financial_obligations where id=new.obligation_id;

  if v_settlement_book is null or v_obligation_book is null then
    raise exception 'Settlement and obligation are required.' using errcode='23503';
  end if;
  if v_settlement_state<>'confirmed' then
    raise exception 'Only confirmed settlements may satisfy obligations.' using errcode='23514';
  end if;
  if v_obligation_state in ('settled','forgiven','written_off','voided') then
    raise exception 'Terminal obligation cannot accept another settlement allocation.' using errcode='23514';
  end if;
  if v_settlement_book<>v_obligation_book or v_settlement_currency<>v_obligation_currency
     or new.currency<>v_settlement_currency then
    raise exception 'Settlement allocation must stay within one accounting book and currency.' using errcode='23514';
  end if;

  select coalesce(sum(a.applied_amount),0) into v_settlement_used
  from atlas.financial_settlement_allocations a
  where a.settlement_id=new.settlement_id;
  if v_settlement_used+new.applied_amount>v_settlement_amount then
    raise exception 'Settlement allocations may not exceed the confirmed settlement amount.' using errcode='23514';
  end if;

  select coalesce(sum(a.applied_amount),0) into v_obligation_used
  from atlas.financial_settlement_allocations a
  join atlas.financial_settlements s on s.id=a.settlement_id and s.settlement_state='confirmed'
  where a.obligation_id=new.obligation_id;
  if v_obligation_used+new.applied_amount>v_obligation_amount then
    raise exception 'Confirmed settlement allocations may not exceed the obligation face amount.' using errcode='23514';
  end if;

  return new;
end;
$$;
revoke all on function atlas.guard_financial_settlement_allocation_v1() from public,anon,authenticated;
drop trigger if exists financial_settlement_allocations_guard_v1 on atlas.financial_settlement_allocations;
create trigger financial_settlement_allocations_guard_v1
before insert on atlas.financial_settlement_allocations
for each row execute function atlas.guard_financial_settlement_allocation_v1();

create or replace function atlas.refresh_financial_obligation_settlement_state_core_v1(p_obligation_id uuid)
returns text
language plpgsql
security definer
set search_path=''
as $$
declare
  v_face numeric;
  v_current text;
  v_applied numeric;
  v_next text;
begin
  select face_amount,settlement_state into v_face,v_current
  from atlas.financial_obligations
  where id=p_obligation_id
  for update;
  if v_face is null then raise exception 'Financial obligation not found.' using errcode='P0002'; end if;
  if v_current in ('forgiven','written_off','voided') then return v_current; end if;

  select coalesce(sum(a.applied_amount),0) into v_applied
  from atlas.financial_settlement_allocations a
  join atlas.financial_settlements s
    on s.id=a.settlement_id
   and s.settlement_state='confirmed'
  where a.obligation_id=p_obligation_id;

  v_next:=case when v_applied=0 then 'open' when v_applied<v_face then 'partially_settled' else 'settled' end;
  update atlas.financial_obligations set settlement_state=v_next,updated_at=now() where id=p_obligation_id;
  return v_next;
end;
$$;
revoke all on function atlas.refresh_financial_obligation_settlement_state_core_v1(uuid)
  from public,anon,authenticated;
grant execute on function atlas.refresh_financial_obligation_settlement_state_core_v1(uuid) to service_role;

create or replace function atlas.guard_financial_settlement_lineage_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_child_book uuid;
  v_parent_book uuid;
  v_cycle boolean;
begin
  select accounting_book_id into v_child_book from atlas.financial_settlements where id=new.child_settlement_id;
  select accounting_book_id into v_parent_book from atlas.financial_settlements where id=new.parent_settlement_id;
  if v_child_book is null or v_parent_book is null or v_child_book<>v_parent_book then
    raise exception 'Settlement lineage must remain within one accounting book.' using errcode='23514';
  end if;

  with recursive ancestors(id) as (
    select new.parent_settlement_id
    union
    select l.parent_settlement_id
    from atlas.financial_settlement_lineage l
    join ancestors a on a.id=l.child_settlement_id
  )
  select exists(select 1 from ancestors where id=new.child_settlement_id) into v_cycle;
  if v_cycle then raise exception 'Settlement lineage may not contain a cycle.' using errcode='23514'; end if;
  return new;
end;
$$;
revoke all on function atlas.guard_financial_settlement_lineage_v1() from public,anon,authenticated;
drop trigger if exists financial_settlement_lineage_guard_v1 on atlas.financial_settlement_lineage;
create trigger financial_settlement_lineage_guard_v1
before insert on atlas.financial_settlement_lineage
for each row execute function atlas.guard_financial_settlement_lineage_v1();

create or replace function atlas.guard_financial_bundle_item_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_bundle_book uuid;
  v_bundle_currency text;
  v_bundle_state text;
  v_settlement_book uuid;
  v_settlement_currency text;
  v_settlement_amount numeric;
  v_settlement_state text;
begin
  select accounting_book_id,currency,bundle_state
    into v_bundle_book,v_bundle_currency,v_bundle_state
  from atlas.financial_settlement_bundles where id=new.bundle_id;
  select accounting_book_id,currency,amount,settlement_state
    into v_settlement_book,v_settlement_currency,v_settlement_amount,v_settlement_state
  from atlas.financial_settlements where id=new.settlement_id;
  if v_bundle_state<>'open' then raise exception 'Only open settlement bundles may accept items.' using errcode='55000'; end if;
  if v_settlement_state<>'confirmed' then raise exception 'Bundle items require confirmed settlements.' using errcode='23514'; end if;
  if v_bundle_book<>v_settlement_book or v_bundle_currency<>v_settlement_currency then
    raise exception 'Settlement bundle item must share book and currency.' using errcode='23514';
  end if;
  if abs(new.signed_net_effect)>v_settlement_amount then
    raise exception 'Bundle item net effect may not exceed its settlement amount.' using errcode='23514';
  end if;
  return new;
end;
$$;
revoke all on function atlas.guard_financial_bundle_item_v1() from public,anon,authenticated;
drop trigger if exists financial_settlement_bundle_items_guard_v1 on atlas.financial_settlement_bundle_items;
create trigger financial_settlement_bundle_items_guard_v1
before insert on atlas.financial_settlement_bundle_items
for each row execute function atlas.guard_financial_bundle_item_v1();

create trigger financial_settlement_bundle_items_immutable_v1
before update or delete on atlas.financial_settlement_bundle_items
for each row execute function atlas.prevent_financial_append_only_mutation_v1();
