-- Atlas governed resource funds / custody kernel v1
--
-- One accounting engine must serve materially different resource postures:
--   * reporting-entity-owned, unrestricted resources
--   * reporting-entity-owned resources constrained by an external party (donor/grantor/etc.)
--   * reporting-entity-owned resources internally designated by governance
--   * third-party resources merely held in custody (client trust, tenant deposit, escrow, etc.)
--
-- This layer is downstream of Reality identity and upstream of financial reporting. It does not
-- create people/organizations, rewrite source evidence, or turn custodial money into revenue.
-- Canonical parties are always reality.entities.

create table if not exists atlas.accounting_resource_pools (
  id uuid primary key default gen_random_uuid(),
  accounting_book_id uuid not null references atlas.accounting_books(id) on delete restrict,
  pool_key text not null,
  pool_name text not null,
  ownership_posture text not null,
  governance_posture text not null,
  nonprofit_net_asset_class text,
  custody_asset_account_id uuid references atlas.accounting_accounts(id) on delete restrict,
  custody_liability_account_id uuid references atlas.accounting_accounts(id) on delete restrict,
  pool_state text not null default 'active',
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint accounting_resource_pools_key_nonempty check (btrim(pool_key)<>''),
  constraint accounting_resource_pools_name_nonempty check (btrim(pool_name)<>''),
  constraint accounting_resource_pools_ownership_check check (
    ownership_posture in ('reporting_entity_owned','third_party_custody')
  ),
  constraint accounting_resource_pools_governance_check check (
    governance_posture in ('unrestricted','externally_restricted','internally_designated','custodial')
  ),
  constraint accounting_resource_pools_posture_pair_check check (
    (ownership_posture='third_party_custody' and governance_posture='custodial')
    or (ownership_posture='reporting_entity_owned' and governance_posture<>'custodial')
  ),
  constraint accounting_resource_pools_net_asset_class_check check (
    nonprofit_net_asset_class is null
    or nonprofit_net_asset_class in ('without_donor_restrictions','with_donor_restrictions')
  ),
  constraint accounting_resource_pools_custody_accounts_check check (
    (ownership_posture='third_party_custody' and custody_asset_account_id is not null and custody_liability_account_id is not null)
    or (ownership_posture='reporting_entity_owned' and custody_asset_account_id is null and custody_liability_account_id is null)
  ),
  constraint accounting_resource_pools_state_check check (pool_state in ('active','closed')),
  constraint accounting_resource_pools_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint accounting_resource_pools_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(accounting_book_id,pool_key)
);

create index if not exists accounting_resource_pools_book_idx
  on atlas.accounting_resource_pools(accounting_book_id,pool_state,ownership_posture,governance_posture);

create table if not exists atlas.accounting_resource_constraints (
  id uuid primary key default gen_random_uuid(),
  resource_pool_id uuid not null references atlas.accounting_resource_pools(id) on delete restrict,
  constraint_key text not null,
  constraint_kind text not null,
  imposed_by_entity_id uuid references reality.entities(id) on delete restrict,
  constraint_state text not null default 'active',
  purpose_text text,
  starts_on date,
  ends_on date,
  evidence_record_id uuid references atlas.evidence_records(id) on delete restrict,
  rule_spec jsonb not null default '{}'::jsonb,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint accounting_resource_constraints_key_nonempty check (btrim(constraint_key)<>''),
  constraint accounting_resource_constraints_kind_check check (
    constraint_kind in ('purpose','time','purpose_and_time','perpetual','contractual','legal_custody','internal_designation','other')
  ),
  constraint accounting_resource_constraints_state_check check (
    constraint_state in ('active','satisfied','released','expired','retired')
  ),
  constraint accounting_resource_constraints_purpose_nonempty check (purpose_text is null or btrim(purpose_text)<>''),
  constraint accounting_resource_constraints_dates_check check (starts_on is null or ends_on is null or ends_on>=starts_on),
  constraint accounting_resource_constraints_rule_object check (jsonb_typeof(rule_spec)='object'),
  constraint accounting_resource_constraints_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint accounting_resource_constraints_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(resource_pool_id,constraint_key)
);

create index if not exists accounting_resource_constraints_pool_idx
  on atlas.accounting_resource_constraints(resource_pool_id,constraint_state,constraint_kind);

create table if not exists atlas.accounting_resource_pool_ledger_scopes (
  id uuid primary key default gen_random_uuid(),
  resource_pool_id uuid not null references atlas.accounting_resource_pools(id) on delete restrict,
  ledger_id uuid not null references ledger.ledgers(id) on delete restrict,
  scope_state text not null default 'active',
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  began_at timestamptz not null default now(),
  ended_at timestamptz,
  constraint accounting_resource_pool_ledger_scopes_state_check check (scope_state in ('active','retired')),
  constraint accounting_resource_pool_ledger_scopes_end_check check (
    (scope_state='active' and ended_at is null) or (scope_state='retired' and ended_at is not null)
  ),
  constraint accounting_resource_pool_ledger_scopes_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint accounting_resource_pool_ledger_scopes_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(resource_pool_id,ledger_id)
);

create table if not exists atlas.accounting_resource_interests (
  id uuid primary key default gen_random_uuid(),
  resource_pool_id uuid not null references atlas.accounting_resource_pools(id) on delete restrict,
  interest_key text not null,
  interest_kind text not null,
  holder_entity_id uuid not null references reality.entities(id) on delete restrict,
  ledger_id uuid references ledger.ledgers(id) on delete restrict,
  context_kind text,
  context_key text,
  interest_state text not null default 'active',
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  began_at timestamptz not null default now(),
  ended_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint accounting_resource_interests_key_nonempty check (btrim(interest_key)<>''),
  constraint accounting_resource_interests_kind_check check (
    interest_kind in ('beneficiary','restrictor','grantor','client','tenant','escrow_party','designator','other')
  ),
  constraint accounting_resource_interests_context_pair_check check (
    (context_kind is null and context_key is null)
    or (context_kind is not null and btrim(context_kind)<>'' and context_key is not null and btrim(context_key)<>'')
  ),
  constraint accounting_resource_interests_state_check check (interest_state in ('active','closed')),
  constraint accounting_resource_interests_end_check check (
    (interest_state='active' and ended_at is null) or (interest_state='closed' and ended_at is not null)
  ),
  constraint accounting_resource_interests_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint accounting_resource_interests_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(resource_pool_id,interest_key)
);

create index if not exists accounting_resource_interests_holder_idx
  on atlas.accounting_resource_interests(holder_entity_id,interest_state,resource_pool_id);
create index if not exists accounting_resource_interests_pool_idx
  on atlas.accounting_resource_interests(resource_pool_id,interest_state,holder_entity_id);

create table if not exists atlas.accounting_resource_source_links (
  id uuid primary key default gen_random_uuid(),
  resource_pool_id uuid not null references atlas.accounting_resource_pools(id) on delete restrict,
  source_domain text not null,
  source_kind text not null,
  source_id text not null,
  relation_kind text not null,
  related_entity_id uuid references reality.entities(id) on delete restrict,
  evidence_record_id uuid references atlas.evidence_records(id) on delete restrict,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint accounting_resource_source_links_domain_nonempty check (btrim(source_domain)<>''),
  constraint accounting_resource_source_links_kind_nonempty check (btrim(source_kind)<>''),
  constraint accounting_resource_source_links_id_nonempty check (btrim(source_id)<>''),
  constraint accounting_resource_source_links_relation_nonempty check (btrim(relation_kind)<>''),
  constraint accounting_resource_source_links_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint accounting_resource_source_links_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(resource_pool_id,source_domain,source_kind,source_id,relation_kind)
);

create table if not exists atlas.accounting_resource_movements (
  id uuid primary key default gen_random_uuid(),
  journal_line_id uuid not null references atlas.accounting_journal_lines(id) on delete restrict,
  resource_pool_id uuid not null references atlas.accounting_resource_pools(id) on delete restrict,
  resource_interest_id uuid references atlas.accounting_resource_interests(id) on delete restrict,
  movement_kind text not null,
  amount_delta numeric not null,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint accounting_resource_movements_kind_check check (
    movement_kind in ('increase','decrease','release','reclassification','custody_increase','custody_decrease','adjustment')
  ),
  constraint accounting_resource_movements_amount_nonzero check (amount_delta<>0),
  constraint accounting_resource_movements_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint accounting_resource_movements_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(journal_line_id,resource_pool_id,resource_interest_id,movement_kind)
);

create index if not exists accounting_resource_movements_pool_idx
  on atlas.accounting_resource_movements(resource_pool_id,resource_interest_id,journal_line_id);

create table if not exists atlas.accounting_custody_reconciliations (
  id uuid primary key default gen_random_uuid(),
  resource_pool_id uuid not null references atlas.accounting_resource_pools(id) on delete restrict,
  reconciliation_on date not null,
  bank_statement_balance numeric not null,
  bank_statement_evidence_id uuid references atlas.evidence_records(id) on delete restrict,
  control_liability_balance numeric not null,
  beneficiary_subledger_balance numeric not null,
  reconciliation_state text not null,
  variance_bank_to_control numeric not null,
  variance_control_to_subledger numeric not null,
  prepared_by_principal_id uuid references atlas.principals(id) on delete restrict,
  prepared_by_user_id uuid references auth.users(id) on delete set null,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint accounting_custody_reconciliations_state_check check (reconciliation_state in ('balanced','exception')),
  constraint accounting_custody_reconciliations_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint accounting_custody_reconciliations_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(resource_pool_id,reconciliation_on)
);

alter table atlas.accounting_resource_pools enable row level security;
alter table atlas.accounting_resource_constraints enable row level security;
alter table atlas.accounting_resource_pool_ledger_scopes enable row level security;
alter table atlas.accounting_resource_interests enable row level security;
alter table atlas.accounting_resource_source_links enable row level security;
alter table atlas.accounting_resource_movements enable row level security;
alter table atlas.accounting_custody_reconciliations enable row level security;

revoke all on table atlas.accounting_resource_pools from public,anon,authenticated;
revoke all on table atlas.accounting_resource_constraints from public,anon,authenticated;
revoke all on table atlas.accounting_resource_pool_ledger_scopes from public,anon,authenticated;
revoke all on table atlas.accounting_resource_interests from public,anon,authenticated;
revoke all on table atlas.accounting_resource_source_links from public,anon,authenticated;
revoke all on table atlas.accounting_resource_movements from public,anon,authenticated;
revoke all on table atlas.accounting_custody_reconciliations from public,anon,authenticated;

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

revoke all on function atlas.guard_accounting_resource_pool_v1() from public,anon,authenticated;
drop trigger if exists accounting_resource_pool_guard_v1 on atlas.accounting_resource_pools;
create trigger accounting_resource_pool_guard_v1
before insert or update on atlas.accounting_resource_pools
for each row execute function atlas.guard_accounting_resource_pool_v1();

create or replace function atlas.guard_accounting_resource_constraint_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_posture text;
  v_identity_state text;
begin
  select governance_posture into v_posture from atlas.accounting_resource_pools where id=new.resource_pool_id;
  if v_posture is null then raise exception 'Resource pool not found.' using errcode='23503'; end if;

  if new.imposed_by_entity_id is not null then
    select identity_state into v_identity_state from reality.entities where id=new.imposed_by_entity_id;
    if v_identity_state<>'canonical' then
      raise exception 'Resource constraint party must be a canonical Reality entity.' using errcode='23514';
    end if;
  end if;

  if new.constraint_kind='legal_custody' and v_posture<>'custodial' then
    raise exception 'Legal custody constraints require a custodial resource pool.' using errcode='23514';
  end if;
  if new.constraint_kind='internal_designation' and v_posture<>'internally_designated' then
    raise exception 'Internal-designation constraints require an internally designated pool.' using errcode='23514';
  end if;
  if new.constraint_kind in ('purpose','time','purpose_and_time','perpetual') and v_posture='unrestricted' then
    raise exception 'Externally meaningful restrictions may not be attached to an unrestricted pool.' using errcode='23514';
  end if;
  new.updated_at:=now();
  return new;
end;
$$;

revoke all on function atlas.guard_accounting_resource_constraint_v1() from public,anon,authenticated;
drop trigger if exists accounting_resource_constraint_guard_v1 on atlas.accounting_resource_constraints;
create trigger accounting_resource_constraint_guard_v1
before insert or update on atlas.accounting_resource_constraints
for each row execute function atlas.guard_accounting_resource_constraint_v1();

create or replace function atlas.guard_accounting_resource_interest_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_identity_state text;
  v_book_id uuid;
  v_pool_posture text;
  v_ledger_allowed boolean;
begin
  select identity_state into v_identity_state from reality.entities where id=new.holder_entity_id;
  if v_identity_state<>'canonical' then
    raise exception 'Resource interest holder must be a canonical Reality entity.' using errcode='23514';
  end if;
  select accounting_book_id,ownership_posture into v_book_id,v_pool_posture
  from atlas.accounting_resource_pools where id=new.resource_pool_id;
  if v_book_id is null then raise exception 'Resource pool not found.' using errcode='23503'; end if;
  if v_pool_posture='third_party_custody' and new.interest_kind not in ('beneficiary','client','tenant','escrow_party','other') then
    raise exception 'Custodial resource interests must identify the party whose funds are held.' using errcode='23514';
  end if;
  if new.ledger_id is not null then
    select exists(
      select 1 from atlas.accounting_book_ledger_scopes s
      where s.accounting_book_id=v_book_id and s.ledger_id=new.ledger_id
        and s.scope_state='active' and s.ended_at is null
    ) into v_ledger_allowed;
    if not v_ledger_allowed then
      raise exception 'Resource-interest Ledger must be in the accounting book scope.' using errcode='23514';
    end if;
  end if;
  new.updated_at:=now();
  return new;
end;
$$;

revoke all on function atlas.guard_accounting_resource_interest_v1() from public,anon,authenticated;
drop trigger if exists accounting_resource_interest_guard_v1 on atlas.accounting_resource_interests;
create trigger accounting_resource_interest_guard_v1
before insert or update on atlas.accounting_resource_interests
for each row execute function atlas.guard_accounting_resource_interest_v1();

create or replace function atlas.guard_accounting_resource_movement_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_entry_state text;
  v_book_id uuid;
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
    if v_credit>0 and new.amount_delta<=0 then
      raise exception 'Credit to custodial liability must increase the beneficiary subledger.' using errcode='23514';
    end if;
    if v_debit>0 and new.amount_delta>=0 then
      raise exception 'Debit to custodial liability must decrease the beneficiary subledger.' using errcode='23514';
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

revoke all on function atlas.guard_accounting_resource_movement_v1() from public,anon,authenticated;
drop trigger if exists accounting_resource_movement_guard_v1 on atlas.accounting_resource_movements;
create trigger accounting_resource_movement_guard_v1
before insert or update or delete on atlas.accounting_resource_movements
for each row execute function atlas.guard_accounting_resource_movement_v1();

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

  -- A custodial client/beneficiary may never consume another beneficiary's money.
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

revoke all on function atlas.guard_accounting_resource_posting_v1() from public,anon,authenticated;
drop trigger if exists accounting_resource_posting_guard_v1 on atlas.accounting_journal_entries;
create trigger accounting_resource_posting_guard_v1
before update of entry_state on atlas.accounting_journal_entries
for each row execute function atlas.guard_accounting_resource_posting_v1();

create or replace function atlas.prevent_posted_resource_movement_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_state text;
begin
  select e.entry_state into v_state
  from atlas.accounting_journal_lines l
  join atlas.accounting_journal_entries e on e.id=l.journal_entry_id
  where l.id=old.journal_line_id;
  if v_state in ('posted','cancelled') then
    raise exception 'Resource movements of posted/cancelled entries are immutable.' using errcode='55000';
  end if;
  return case when tg_op='DELETE' then old else new end;
end;
$$;

revoke all on function atlas.prevent_posted_resource_movement_mutation_v1() from public,anon,authenticated;
