-- Atlas double-entry accounting book + journal v1
--
-- Accounting is downstream interpretation. Reality, financial-source evidence, commercial truth,
-- Spend, and operational Ledgers remain authoritative in their own domains. A posted accounting
-- entry is an immutable balanced projection for financial reporting. Corrections are new entries
-- (normally reversals/adjustments), never silent rewrites of posted history.

create table if not exists atlas.accounting_books (
  id uuid primary key default gen_random_uuid(),
  reporting_entity_id uuid not null references reality.entities(id) on delete restrict,
  stable_key text not null,
  book_name text not null,
  base_currency text not null,
  accounting_basis text not null default 'cash',
  fiscal_year_start_month integer not null default 1,
  book_state text not null default 'active',
  created_by_user_id uuid references auth.users(id) on delete set null,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint accounting_books_stable_key_nonempty check (btrim(stable_key)<>''),
  constraint accounting_books_name_nonempty check (btrim(book_name)<>''),
  constraint accounting_books_currency_check check (base_currency ~ '^[A-Z]{3}$'),
  constraint accounting_books_basis_check check (accounting_basis in ('cash','accrual')),
  constraint accounting_books_fiscal_month_check check (fiscal_year_start_month between 1 and 12),
  constraint accounting_books_state_check check (book_state in ('active','retired')),
  constraint accounting_books_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint accounting_books_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(reporting_entity_id,stable_key)
);

create table if not exists atlas.accounting_book_ledger_scopes (
  id uuid primary key default gen_random_uuid(),
  accounting_book_id uuid not null references atlas.accounting_books(id) on delete restrict,
  ledger_id uuid not null references ledger.ledgers(id) on delete restrict,
  scope_state text not null default 'active',
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  began_at timestamptz not null default now(),
  ended_at timestamptz,
  constraint accounting_book_ledger_scopes_state_check check (scope_state in ('active','retired')),
  constraint accounting_book_ledger_scopes_end_check check (
    (scope_state='active' and ended_at is null) or (scope_state='retired' and ended_at is not null)
  ),
  constraint accounting_book_ledger_scopes_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint accounting_book_ledger_scopes_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(accounting_book_id,ledger_id)
);

create index if not exists accounting_book_ledger_scopes_ledger_idx
  on atlas.accounting_book_ledger_scopes(ledger_id,scope_state,accounting_book_id);

create table if not exists atlas.accounting_accounts (
  id uuid primary key default gen_random_uuid(),
  accounting_book_id uuid not null references atlas.accounting_books(id) on delete restrict,
  account_key text not null,
  account_code text,
  account_name text not null,
  account_class text not null,
  account_subtype text,
  parent_account_id uuid references atlas.accounting_accounts(id) on delete restrict,
  normal_balance text not null,
  account_state text not null default 'active',
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint accounting_accounts_key_nonempty check (btrim(account_key)<>''),
  constraint accounting_accounts_code_nonempty check (account_code is null or btrim(account_code)<>''),
  constraint accounting_accounts_name_nonempty check (btrim(account_name)<>''),
  constraint accounting_accounts_class_check check (account_class in ('asset','liability','equity','revenue','expense')),
  constraint accounting_accounts_subtype_nonempty check (account_subtype is null or btrim(account_subtype)<>''),
  constraint accounting_accounts_normal_balance_check check (normal_balance in ('debit','credit')),
  constraint accounting_accounts_state_check check (account_state in ('active','inactive')),
  constraint accounting_accounts_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint accounting_accounts_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(accounting_book_id,account_key)
);

create unique index if not exists accounting_accounts_code_uq
  on atlas.accounting_accounts(accounting_book_id,account_code)
  where account_code is not null;
create index if not exists accounting_accounts_parent_idx
  on atlas.accounting_accounts(parent_account_id,accounting_book_id);

create table if not exists atlas.accounting_periods (
  id uuid primary key default gen_random_uuid(),
  accounting_book_id uuid not null references atlas.accounting_books(id) on delete restrict,
  period_key text not null,
  period_start_on date not null,
  period_end_on date not null,
  period_state text not null default 'open',
  closed_at timestamptz,
  closed_by_user_id uuid references auth.users(id) on delete set null,
  locked_at timestamptz,
  locked_by_user_id uuid references auth.users(id) on delete set null,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint accounting_periods_key_nonempty check (btrim(period_key)<>''),
  constraint accounting_periods_range_check check (period_end_on>=period_start_on),
  constraint accounting_periods_state_check check (period_state in ('open','closed','locked')),
  constraint accounting_periods_closed_fields_check check (
    (period_state='open' and closed_at is null and locked_at is null)
    or (period_state='closed' and closed_at is not null and locked_at is null)
    or (period_state='locked' and closed_at is not null and locked_at is not null)
  ),
  constraint accounting_periods_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint accounting_periods_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(accounting_book_id,period_key)
);

create index if not exists accounting_periods_book_range_idx
  on atlas.accounting_periods(accounting_book_id,period_start_on,period_end_on,period_state);

create table if not exists atlas.accounting_journal_entries (
  id uuid primary key default gen_random_uuid(),
  accounting_book_id uuid not null references atlas.accounting_books(id) on delete restrict,
  client_entry_key text not null,
  entry_date date not null,
  entry_kind text not null default 'standard',
  entry_state text not null default 'draft',
  memo text,
  input_sha256 text not null,
  reversal_of_entry_id uuid references atlas.accounting_journal_entries(id) on delete restrict,
  created_by_user_id uuid references auth.users(id) on delete set null,
  posted_by_principal_id uuid references atlas.principals(id) on delete restrict,
  posted_by_user_id uuid references auth.users(id) on delete set null,
  posted_at timestamptz,
  cancelled_at timestamptz,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint accounting_journal_entries_client_key_nonempty check (btrim(client_entry_key)<>''),
  constraint accounting_journal_entries_kind_check check (entry_kind in ('standard','adjusting','reversal','opening','source_projection')),
  constraint accounting_journal_entries_state_check check (entry_state in ('draft','posted','cancelled')),
  constraint accounting_journal_entries_memo_nonempty check (memo is null or btrim(memo)<>''),
  constraint accounting_journal_entries_hash_check check (input_sha256 ~ '^[0-9a-f]{64}$'),
  constraint accounting_journal_entries_posted_fields_check check (
    (entry_state='draft' and posted_at is null and posted_by_principal_id is null and cancelled_at is null)
    or (entry_state='posted' and posted_at is not null and posted_by_principal_id is not null and cancelled_at is null)
    or (entry_state='cancelled' and posted_at is null and cancelled_at is not null)
  ),
  constraint accounting_journal_entries_reversal_kind_check check (
    reversal_of_entry_id is null or entry_kind='reversal'
  ),
  constraint accounting_journal_entries_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint accounting_journal_entries_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(accounting_book_id,client_entry_key)
);

create unique index if not exists accounting_journal_entries_one_reversal_uq
  on atlas.accounting_journal_entries(reversal_of_entry_id)
  where reversal_of_entry_id is not null and entry_state='posted';
create index if not exists accounting_journal_entries_book_date_idx
  on atlas.accounting_journal_entries(accounting_book_id,entry_date,entry_state,id);

create table if not exists atlas.accounting_journal_lines (
  id uuid primary key default gen_random_uuid(),
  journal_entry_id uuid not null references atlas.accounting_journal_entries(id) on delete restrict,
  line_ordinal integer not null,
  accounting_account_id uuid not null references atlas.accounting_accounts(id) on delete restrict,
  debit_amount numeric not null default 0,
  credit_amount numeric not null default 0,
  memo text,
  ledger_id uuid references ledger.ledgers(id) on delete restrict,
  subject_entity_id uuid references reality.entities(id) on delete restrict,
  dimensions jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint accounting_journal_lines_ordinal_check check (line_ordinal>0),
  constraint accounting_journal_lines_amount_check check (
    (debit_amount>0 and credit_amount=0) or (credit_amount>0 and debit_amount=0)
  ),
  constraint accounting_journal_lines_memo_nonempty check (memo is null or btrim(memo)<>''),
  constraint accounting_journal_lines_dimensions_object check (jsonb_typeof(dimensions)='object'),
  constraint accounting_journal_lines_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(journal_entry_id,line_ordinal)
);

create index if not exists accounting_journal_lines_account_idx
  on atlas.accounting_journal_lines(accounting_account_id,journal_entry_id);
create index if not exists accounting_journal_lines_ledger_idx
  on atlas.accounting_journal_lines(ledger_id,journal_entry_id)
  where ledger_id is not null;

create table if not exists atlas.accounting_journal_entry_sources (
  id uuid primary key default gen_random_uuid(),
  journal_entry_id uuid not null references atlas.accounting_journal_entries(id) on delete restrict,
  source_domain text not null,
  source_kind text not null,
  source_id text not null,
  relation_kind text not null default 'basis',
  evidence_record_id uuid references atlas.evidence_records(id) on delete restrict,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint accounting_journal_entry_sources_domain_nonempty check (btrim(source_domain)<>''),
  constraint accounting_journal_entry_sources_kind_nonempty check (btrim(source_kind)<>''),
  constraint accounting_journal_entry_sources_id_nonempty check (btrim(source_id)<>''),
  constraint accounting_journal_entry_sources_relation_nonempty check (btrim(relation_kind)<>''),
  constraint accounting_journal_entry_sources_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint accounting_journal_entry_sources_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(journal_entry_id,source_domain,source_kind,source_id,relation_kind)
);

create index if not exists accounting_journal_entry_sources_source_idx
  on atlas.accounting_journal_entry_sources(source_domain,source_kind,source_id,journal_entry_id);

alter table atlas.accounting_books enable row level security;
alter table atlas.accounting_book_ledger_scopes enable row level security;
alter table atlas.accounting_accounts enable row level security;
alter table atlas.accounting_periods enable row level security;
alter table atlas.accounting_journal_entries enable row level security;
alter table atlas.accounting_journal_lines enable row level security;
alter table atlas.accounting_journal_entry_sources enable row level security;

revoke all on table atlas.accounting_books from public,anon,authenticated;
revoke all on table atlas.accounting_book_ledger_scopes from public,anon,authenticated;
revoke all on table atlas.accounting_accounts from public,anon,authenticated;
revoke all on table atlas.accounting_periods from public,anon,authenticated;
revoke all on table atlas.accounting_journal_entries from public,anon,authenticated;
revoke all on table atlas.accounting_journal_lines from public,anon,authenticated;
revoke all on table atlas.accounting_journal_entry_sources from public,anon,authenticated;

create or replace function atlas.accounting_book_authorized_self_v1(p_accounting_book_id uuid)
returns boolean
language sql
stable
security definer
set search_path=pg_catalog,atlas,auth,reality,ledger
as $$
  with context as (
    select atlas.current_person_id_v1() as person_id
  ), book as (
    select b.id,b.reporting_entity_id
    from atlas.accounting_books b
    where b.id=p_accounting_book_id and b.book_state='active'
  ), seat_scope as (
    select distinct l.subject_entity_id
    from atlas.accounting_book_ledger_scopes scope
    join ledger.ledgers l on l.id=scope.ledger_id and l.ledger_state='active' and l.retired_at is null
    join context c on true
    join ledger.seats seat
      on seat.ledger_id=scope.ledger_id
     and seat.person_entity_id=c.person_id
     and seat.seat_state='active'
     and seat.ended_at is null
    where scope.accounting_book_id=p_accounting_book_id
      and scope.scope_state='active'
      and scope.ended_at is null
  )
  select auth.uid() is not null
     and exists(select 1 from seat_scope)
     and exists(
       select 1
       from book b
       join context c on true
       where b.reporting_entity_id=c.person_id
          or exists(select 1 from seat_scope s where s.subject_entity_id=b.reporting_entity_id)
          or exists(
            select 1
            from reality.responsibility_relations r
            where r.carrier_person_entity_id=c.person_id
              and r.relation_state='active'
              and r.jurisdiction_kind='entity'
              and r.jurisdiction_entity_id=b.reporting_entity_id
              and r.began_at<=now()
              and r.ended_at is null
              and r.permitted_operations @> array['accounting.manage']::text[]
          )
     );
$$;

revoke all on function atlas.accounting_book_authorized_self_v1(uuid) from public,anon,authenticated,service_role;
grant execute on function atlas.accounting_book_authorized_self_v1(uuid) to authenticated,service_role;

create or replace function atlas.guard_accounting_account_parent_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $$
declare
  v_parent_book uuid;
  v_cursor uuid;
begin
  if new.parent_account_id is null then return new; end if;
  if new.parent_account_id=new.id then
    raise exception 'An accounting account cannot parent itself.' using errcode='23514';
  end if;
  select accounting_book_id into v_parent_book
  from atlas.accounting_accounts where id=new.parent_account_id;
  if v_parent_book is null or v_parent_book<>new.accounting_book_id then
    raise exception 'Accounting account parent must belong to the same book.' using errcode='23514';
  end if;

  v_cursor:=new.parent_account_id;
  while v_cursor is not null loop
    if v_cursor=new.id then
      raise exception 'Accounting account hierarchy may not contain a cycle.' using errcode='23514';
    end if;
    select parent_account_id into v_cursor
    from atlas.accounting_accounts where id=v_cursor;
  end loop;
  return new;
end;
$$;

revoke all on function atlas.guard_accounting_account_parent_v1() from public,anon,authenticated;
drop trigger if exists accounting_accounts_parent_guard_v1 on atlas.accounting_accounts;
create trigger accounting_accounts_parent_guard_v1
before insert or update of parent_account_id,accounting_book_id
on atlas.accounting_accounts
for each row execute function atlas.guard_accounting_account_parent_v1();

create or replace function atlas.guard_accounting_period_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $$
begin
  if exists(
    select 1
    from atlas.accounting_periods p
    where p.accounting_book_id=new.accounting_book_id
      and p.id<>new.id
      and daterange(p.period_start_on,p.period_end_on,'[]') && daterange(new.period_start_on,new.period_end_on,'[]')
  ) then
    raise exception 'Accounting periods may not overlap within one book.' using errcode='23514';
  end if;
  new.updated_at:=now();
  return new;
end;
$$;

revoke all on function atlas.guard_accounting_period_v1() from public,anon,authenticated;
drop trigger if exists accounting_periods_guard_v1 on atlas.accounting_periods;
create trigger accounting_periods_guard_v1
before insert or update on atlas.accounting_periods
for each row execute function atlas.guard_accounting_period_v1();

create or replace function atlas.guard_accounting_journal_entry_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $$
begin
  if tg_op='DELETE' then
    if old.entry_state<>'draft' then
      raise exception 'Posted or cancelled accounting entries are immutable.' using errcode='55000';
    end if;
    return old;
  end if;

  if old.entry_state in ('posted','cancelled') then
    raise exception 'Posted or cancelled accounting entries are immutable.' using errcode='55000';
  end if;
  if old.accounting_book_id is distinct from new.accounting_book_id
     or old.client_entry_key is distinct from new.client_entry_key
     or old.reversal_of_entry_id is distinct from new.reversal_of_entry_id then
    raise exception 'Accounting entry identity is immutable.' using errcode='23514';
  end if;
  if new.entry_state not in ('draft','posted','cancelled') then
    raise exception 'Invalid accounting entry state.' using errcode='23514';
  end if;
  new.updated_at:=now();
  return new;
end;
$$;

revoke all on function atlas.guard_accounting_journal_entry_mutation_v1() from public,anon,authenticated;
drop trigger if exists accounting_journal_entries_mutation_guard_v1 on atlas.accounting_journal_entries;
create trigger accounting_journal_entries_mutation_guard_v1
before update or delete on atlas.accounting_journal_entries
for each row execute function atlas.guard_accounting_journal_entry_mutation_v1();

create or replace function atlas.guard_accounting_journal_line_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $$
declare
  v_entry_book uuid;
  v_entry_state text;
  v_account_book uuid;
  v_account_state text;
  v_ledger_allowed boolean;
begin
  select e.accounting_book_id,e.entry_state into v_entry_book,v_entry_state
  from atlas.accounting_journal_entries e
  where e.id=coalesce(new.journal_entry_id,old.journal_entry_id);
  if v_entry_book is null then
    raise exception 'Accounting journal entry not found.' using errcode='23503';
  end if;
  if v_entry_state<>'draft' then
    raise exception 'Lines of posted or cancelled accounting entries are immutable.' using errcode='55000';
  end if;
  if tg_op='DELETE' then return old; end if;

  select a.accounting_book_id,a.account_state into v_account_book,v_account_state
  from atlas.accounting_accounts a where a.id=new.accounting_account_id;
  if v_account_book is null or v_account_book<>v_entry_book or v_account_state<>'active' then
    raise exception 'Journal line account must be active in the same accounting book.' using errcode='23514';
  end if;

  if new.ledger_id is not null then
    select exists(
      select 1 from atlas.accounting_book_ledger_scopes s
      where s.accounting_book_id=v_entry_book
        and s.ledger_id=new.ledger_id
        and s.scope_state='active'
        and s.ended_at is null
    ) into v_ledger_allowed;
    if not v_ledger_allowed then
      raise exception 'Journal line Ledger must be in the accounting book scope.' using errcode='23514';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function atlas.guard_accounting_journal_line_v1() from public,anon,authenticated;
drop trigger if exists accounting_journal_lines_guard_v1 on atlas.accounting_journal_lines;
create trigger accounting_journal_lines_guard_v1
before insert or update or delete on atlas.accounting_journal_lines
for each row execute function atlas.guard_accounting_journal_line_v1();

create or replace function atlas.prevent_accounting_journal_source_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $$
begin
  raise exception 'Accounting journal source links are append-only.' using errcode='55000';
end;
$$;

revoke all on function atlas.prevent_accounting_journal_source_mutation_v1() from public,anon,authenticated;
drop trigger if exists accounting_journal_entry_sources_immutable_v1 on atlas.accounting_journal_entry_sources;
create trigger accounting_journal_entry_sources_immutable_v1
before update or delete on atlas.accounting_journal_entry_sources
for each row execute function atlas.prevent_accounting_journal_source_mutation_v1();

create or replace function atlas.create_accounting_book_self_api_v1(
  p_reporting_entity_id uuid,
  p_stable_key text,
  p_book_name text,
  p_base_currency text,
  p_accounting_basis text,
  p_fiscal_year_start_month integer,
  p_initial_ledger_ids uuid[],
  p_provenance jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth,reality,ledger
as $$
declare
  v_person_id uuid;
  v_key text:=lower(btrim(coalesce(p_stable_key,'')));
  v_name text:=btrim(coalesce(p_book_name,''));
  v_currency text:=upper(btrim(coalesce(p_base_currency,'')));
  v_basis text:=lower(btrim(coalesce(p_accounting_basis,'')));
  v_requested integer;
  v_distinct integer;
  v_ledger_id uuid;
  v_book atlas.accounting_books%rowtype;
  v_reporting reality.entities%rowtype;
  v_reporting_authorized boolean:=false;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null then raise exception 'Canonical Reality Person required.' using errcode='42501'; end if;
  if p_reporting_entity_id is null or v_key='' or v_name='' or v_currency !~ '^[A-Z]{3}$'
     or v_basis not in ('cash','accrual') or p_fiscal_year_start_month not between 1 and 12 then
    raise exception 'Reporting entity, stable key, name, currency, accounting basis, and fiscal-year month are required.' using errcode='22023';
  end if;
  if p_initial_ledger_ids is null or coalesce(array_length(p_initial_ledger_ids,1),0)=0
     or array_length(p_initial_ledger_ids,1)>50 then
    raise exception 'One to fifty initial Ledger scopes are required.' using errcode='22023';
  end if;
  if p_provenance is null or jsonb_typeof(p_provenance)<>'object'
     or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Accounting book provenance and metadata must be JSON objects.' using errcode='22023';
  end if;

  select * into v_reporting from reality.entities e
  where e.id=p_reporting_entity_id and e.identity_state='canonical';
  if v_reporting.id is null then raise exception 'Canonical reporting Reality entity required.' using errcode='23503'; end if;

  select count(*),count(distinct x) into v_requested,v_distinct from unnest(p_initial_ledger_ids) x;
  if v_requested<>v_distinct or exists(select 1 from unnest(p_initial_ledger_ids) x where x is null) then
    raise exception 'Initial Ledger scopes must be non-null and unique.' using errcode='22023';
  end if;

  foreach v_ledger_id in array p_initial_ledger_ids loop
    if not exists(select 1 from ledger.ledgers l where l.id=v_ledger_id and l.ledger_state='active' and l.retired_at is null) then
      raise exception 'Every initial Ledger scope must be active.' using errcode='23503';
    end if;
    perform atlas.current_active_ledger_seat_v1(v_ledger_id);
    if exists(select 1 from ledger.ledgers l where l.id=v_ledger_id and l.subject_entity_id=p_reporting_entity_id) then
      v_reporting_authorized:=true;
    end if;
  end loop;

  if p_reporting_entity_id=v_person_id then v_reporting_authorized:=true; end if;
  if not v_reporting_authorized then
    select exists(
      select 1 from reality.responsibility_relations r
      where r.carrier_person_entity_id=v_person_id
        and r.relation_state='active'
        and r.jurisdiction_kind='entity'
        and r.jurisdiction_entity_id=p_reporting_entity_id
        and r.began_at<=now()
        and r.ended_at is null
        and r.permitted_operations @> array['accounting.manage']::text[]
    ) into v_reporting_authorized;
  end if;
  if not v_reporting_authorized then
    raise exception 'Accounting responsibility for the reporting entity is required when it is not a scoped Ledger subject.' using errcode='42501';
  end if;

  insert into atlas.accounting_books(
    reporting_entity_id,stable_key,book_name,base_currency,accounting_basis,
    fiscal_year_start_month,created_by_user_id,provenance,metadata
  ) values (
    p_reporting_entity_id,v_key,v_name,v_currency,v_basis,p_fiscal_year_start_month,auth.uid(),
    p_provenance||jsonb_build_object(
      'authority','create_accounting_book_self_api_v1',
      'accountingIsProjectionNotSourceTruth',true
    ),p_metadata
  ) on conflict(reporting_entity_id,stable_key)
  do update set
    book_name=excluded.book_name,
    base_currency=excluded.base_currency,
    accounting_basis=excluded.accounting_basis,
    fiscal_year_start_month=excluded.fiscal_year_start_month,
    book_state='active',
    provenance=atlas.accounting_books.provenance||excluded.provenance,
    metadata=atlas.accounting_books.metadata||excluded.metadata,
    updated_at=now()
  returning * into v_book;

  foreach v_ledger_id in array p_initial_ledger_ids loop
    insert into atlas.accounting_book_ledger_scopes(accounting_book_id,ledger_id,scope_state,provenance)
    values(v_book.id,v_ledger_id,'active',jsonb_build_object('authority','create_accounting_book_self_api_v1'))
    on conflict(accounting_book_id,ledger_id)
    do update set scope_state='active',ended_at=null,updated_at=now();
  end loop;

  return jsonb_build_object(
    'contractVersion','accounting_book_v1',
    'accountingBookId',v_book.id,
    'reportingEntityId',v_book.reporting_entity_id,
    'bookName',v_book.book_name,
    'baseCurrency',v_book.base_currency,
    'accountingBasis',v_book.accounting_basis,
    'truthBoundary',jsonb_build_object(
      'accountingIsProjectionNotReality',true,
      'operationalLedgersRemainIndependent',true,
      'sourceOwnershipDoesNotDetermineReportingEntity',true
    )
  );
end;
$$;

revoke all on function atlas.create_accounting_book_self_api_v1(uuid,text,text,text,text,integer,uuid[],jsonb,jsonb)
  from public,anon;
grant execute on function atlas.create_accounting_book_self_api_v1(uuid,text,text,text,text,integer,uuid[],jsonb,jsonb)
  to authenticated;

create or replace function atlas.upsert_accounting_account_self_api_v1(
  p_accounting_book_id uuid,
  p_account_key text,
  p_account_name text,
  p_account_class text,
  p_normal_balance text,
  p_account_code text default null,
  p_account_subtype text default null,
  p_parent_account_id uuid default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare
  v_key text:=lower(btrim(coalesce(p_account_key,'')));
  v_name text:=btrim(coalesce(p_account_name,''));
  v_class text:=lower(btrim(coalesce(p_account_class,'')));
  v_normal text:=lower(btrim(coalesce(p_normal_balance,'')));
  v_account atlas.accounting_accounts%rowtype;
begin
  if not atlas.accounting_book_authorized_self_v1(p_accounting_book_id) then
    raise exception 'Accounting book authority required.' using errcode='42501';
  end if;
  if v_key='' or v_name='' or v_class not in ('asset','liability','equity','revenue','expense')
     or v_normal not in ('debit','credit') then
    raise exception 'Account key, name, class, and normal balance are required.' using errcode='22023';
  end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Accounting account metadata must be a JSON object.' using errcode='22023';
  end if;

  insert into atlas.accounting_accounts(
    accounting_book_id,account_key,account_code,account_name,account_class,account_subtype,
    parent_account_id,normal_balance,metadata,provenance
  ) values (
    p_accounting_book_id,v_key,nullif(btrim(coalesce(p_account_code,'')),''),v_name,v_class,
    nullif(lower(btrim(coalesce(p_account_subtype,''))),''),p_parent_account_id,v_normal,p_metadata,
    jsonb_build_object('authority','upsert_accounting_account_self_api_v1')
  ) on conflict(accounting_book_id,account_key)
  do update set
    account_code=excluded.account_code,
    account_name=excluded.account_name,
    account_class=excluded.account_class,
    account_subtype=excluded.account_subtype,
    parent_account_id=excluded.parent_account_id,
    normal_balance=excluded.normal_balance,
    account_state='active',
    metadata=atlas.accounting_accounts.metadata||excluded.metadata,
    updated_at=now()
  returning * into v_account;

  return jsonb_build_object(
    'contractVersion','accounting_account_v1',
    'accountingAccountId',v_account.id,
    'accountingBookId',v_account.accounting_book_id,
    'accountKey',v_account.account_key,
    'accountCode',v_account.account_code,
    'accountName',v_account.account_name,
    'accountClass',v_account.account_class,
    'normalBalance',v_account.normal_balance,
    'accountState',v_account.account_state
  );
end;
$$;

revoke all on function atlas.upsert_accounting_account_self_api_v1(uuid,text,text,text,text,text,text,uuid,jsonb)
  from public,anon;
grant execute on function atlas.upsert_accounting_account_self_api_v1(uuid,text,text,text,text,text,text,uuid,jsonb)
  to authenticated;

create or replace function atlas.open_accounting_period_self_api_v1(
  p_accounting_book_id uuid,
  p_period_key text,
  p_period_start_on date,
  p_period_end_on date,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare
  v_period atlas.accounting_periods%rowtype;
  v_key text:=btrim(coalesce(p_period_key,''));
begin
  if not atlas.accounting_book_authorized_self_v1(p_accounting_book_id) then
    raise exception 'Accounting book authority required.' using errcode='42501';
  end if;
  if v_key='' or p_period_start_on is null or p_period_end_on is null or p_period_end_on<p_period_start_on then
    raise exception 'Accounting period key and valid date range are required.' using errcode='22023';
  end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then raise exception 'Accounting period metadata must be an object.' using errcode='22023'; end if;

  select * into v_period from atlas.accounting_periods
  where accounting_book_id=p_accounting_book_id and period_key=v_key
  for update;
  if v_period.id is not null and v_period.period_state='locked' then
    raise exception 'A locked accounting period cannot be reopened or redefined.' using errcode='55000';
  end if;

  insert into atlas.accounting_periods(
    accounting_book_id,period_key,period_start_on,period_end_on,period_state,provenance,metadata
  ) values (
    p_accounting_book_id,v_key,p_period_start_on,p_period_end_on,'open',
    jsonb_build_object('authority','open_accounting_period_self_api_v1'),p_metadata
  ) on conflict(accounting_book_id,period_key)
  do update set
    period_start_on=excluded.period_start_on,
    period_end_on=excluded.period_end_on,
    period_state='open',closed_at=null,closed_by_user_id=null,locked_at=null,locked_by_user_id=null,
    metadata=atlas.accounting_periods.metadata||excluded.metadata,
    updated_at=now()
  returning * into v_period;

  return jsonb_build_object(
    'contractVersion','accounting_period_v1','accountingPeriodId',v_period.id,
    'accountingBookId',v_period.accounting_book_id,'periodKey',v_period.period_key,
    'periodStartOn',v_period.period_start_on,'periodEndOn',v_period.period_end_on,'periodState',v_period.period_state
  );
end;
$$;

revoke all on function atlas.open_accounting_period_self_api_v1(uuid,text,date,date,jsonb) from public,anon;
grant execute on function atlas.open_accounting_period_self_api_v1(uuid,text,date,date,jsonb) to authenticated;

create or replace function atlas.accounting_entry_balance_core_v1(p_journal_entry_id uuid)
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog,atlas
as $$
  select jsonb_build_object(
    'journalEntryId',p_journal_entry_id,
    'lineCount',count(*)::integer,
    'debitTotal',coalesce(sum(line.debit_amount),0),
    'creditTotal',coalesce(sum(line.credit_amount),0),
    'balanced',count(*)>=2 and coalesce(sum(line.debit_amount),0)>0 and coalesce(sum(line.debit_amount),0)=coalesce(sum(line.credit_amount),0)
  )
  from atlas.accounting_journal_lines line
  where line.journal_entry_id=p_journal_entry_id;
$$;

revoke all on function atlas.accounting_entry_balance_core_v1(uuid) from public,anon,authenticated,service_role;

create or replace function atlas.replace_accounting_journal_draft_self_api_v1(
  p_accounting_book_id uuid,
  p_client_entry_key text,
  p_entry_date date,
  p_entry_kind text,
  p_memo text,
  p_lines jsonb,
  p_provenance jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb,
  p_reversal_of_entry_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth,extensions
as $$
declare
  v_key text:=btrim(coalesce(p_client_entry_key,''));
  v_kind text:=lower(btrim(coalesce(p_entry_kind,'standard')));
  v_lines jsonb:=coalesce(p_lines,'[]'::jsonb);
  v_hash text;
  v_existing atlas.accounting_journal_entries%rowtype;
  v_entry atlas.accounting_journal_entries%rowtype;
  v_item jsonb;
  v_ordinal integer:=0;
  v_account_id uuid;
  v_ledger_id uuid;
  v_subject_entity_id uuid;
  v_debit numeric;
  v_credit numeric;
  v_debit_total numeric:=0;
  v_credit_total numeric:=0;
  v_account atlas.accounting_accounts%rowtype;
begin
  if not atlas.accounting_book_authorized_self_v1(p_accounting_book_id) then
    raise exception 'Accounting book authority required.' using errcode='42501';
  end if;
  if v_key='' or p_entry_date is null or v_kind not in ('standard','adjusting','reversal','opening','source_projection')
     or jsonb_typeof(v_lines)<>'array' or jsonb_array_length(v_lines)<2 or jsonb_array_length(v_lines)>200 then
    raise exception 'Entry key, date, supported kind, and two to two hundred lines are required.' using errcode='22023';
  end if;
  if (p_reversal_of_entry_id is null and v_kind='reversal') or (p_reversal_of_entry_id is not null and v_kind<>'reversal') then
    raise exception 'Reversal entry kind and reversal source must be supplied together.' using errcode='22023';
  end if;
  if p_provenance is null or jsonb_typeof(p_provenance)<>'object'
     or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Journal provenance and metadata must be JSON objects.' using errcode='22023';
  end if;

  for v_item in select value from jsonb_array_elements(v_lines)
  loop
    if jsonb_typeof(v_item)<>'object' then raise exception 'Every journal line must be an object.' using errcode='22023'; end if;
    begin
      v_account_id:=(v_item->>'accountingAccountId')::uuid;
      v_debit:=coalesce(nullif(v_item->>'debitAmount','')::numeric,0);
      v_credit:=coalesce(nullif(v_item->>'creditAmount','')::numeric,0);
      v_ledger_id:=nullif(v_item->>'ledgerId','')::uuid;
      v_subject_entity_id:=nullif(v_item->>'subjectEntityId','')::uuid;
    exception when others then
      raise exception 'Journal line account, debit/credit amounts, Ledger, and subject identifiers must use valid types.' using errcode='22023';
    end;
    if not ((v_debit>0 and v_credit=0) or (v_credit>0 and v_debit=0)) then
      raise exception 'Each journal line must contain exactly one positive debit or credit amount.' using errcode='22023';
    end if;
    select * into v_account from atlas.accounting_accounts a
    where a.id=v_account_id and a.accounting_book_id=p_accounting_book_id and a.account_state='active';
    if v_account.id is null then raise exception 'Every journal line account must be active in this book.' using errcode='23503'; end if;
    if v_ledger_id is not null and not exists(
      select 1 from atlas.accounting_book_ledger_scopes s
      where s.accounting_book_id=p_accounting_book_id and s.ledger_id=v_ledger_id
        and s.scope_state='active' and s.ended_at is null
    ) then raise exception 'Journal line Ledger is outside this accounting book.' using errcode='23503'; end if;
    if jsonb_typeof(coalesce(v_item->'dimensions','{}'::jsonb))<>'object'
       or jsonb_typeof(coalesce(v_item->'metadata','{}'::jsonb))<>'object' then
      raise exception 'Journal line dimensions and metadata must be objects.' using errcode='22023';
    end if;
    v_debit_total:=v_debit_total+v_debit;
    v_credit_total:=v_credit_total+v_credit;
  end loop;

  if v_debit_total<=0 or v_debit_total<>v_credit_total then
    raise exception 'Accounting journal drafts must be balanced before they can be saved.' using errcode='23514';
  end if;

  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'bookId',p_accounting_book_id,'entryDate',p_entry_date,'entryKind',v_kind,
    'memo',nullif(btrim(coalesce(p_memo,'')),''),'lines',v_lines,'reversalOf',p_reversal_of_entry_id,
    'metadata',p_metadata
  )::text,'utf8'),'sha256'),'hex');

  select * into v_existing from atlas.accounting_journal_entries e
  where e.accounting_book_id=p_accounting_book_id and e.client_entry_key=v_key
  for update;
  if v_existing.id is not null then
    if v_existing.input_sha256=v_hash then
      return jsonb_build_object(
        'contractVersion','accounting_journal_draft_v1','state','unchanged',
        'journalEntryId',v_existing.id,'entryState',v_existing.entry_state,
        'balance',atlas.accounting_entry_balance_core_v1(v_existing.id)
      );
    end if;
    if v_existing.entry_state<>'draft' then
      raise exception 'A posted or cancelled journal entry key cannot be reused with different content.' using errcode='23514';
    end if;
    delete from atlas.accounting_journal_lines where journal_entry_id=v_existing.id;
    update atlas.accounting_journal_entries e
    set entry_date=p_entry_date,entry_kind=v_kind,memo=nullif(btrim(coalesce(p_memo,'')),''),
        input_sha256=v_hash,provenance=e.provenance||p_provenance,metadata=e.metadata||p_metadata,updated_at=now()
    where e.id=v_existing.id returning * into v_entry;
  else
    insert into atlas.accounting_journal_entries(
      accounting_book_id,client_entry_key,entry_date,entry_kind,entry_state,memo,input_sha256,
      reversal_of_entry_id,created_by_user_id,provenance,metadata
    ) values (
      p_accounting_book_id,v_key,p_entry_date,v_kind,'draft',nullif(btrim(coalesce(p_memo,'')),''),v_hash,
      p_reversal_of_entry_id,auth.uid(),
      p_provenance||jsonb_build_object('authority','replace_accounting_journal_draft_self_api_v1'),p_metadata
    ) returning * into v_entry;
  end if;

  v_ordinal:=0;
  for v_item in select value from jsonb_array_elements(v_lines)
  loop
    v_ordinal:=v_ordinal+1;
    v_account_id:=(v_item->>'accountingAccountId')::uuid;
    v_debit:=coalesce(nullif(v_item->>'debitAmount','')::numeric,0);
    v_credit:=coalesce(nullif(v_item->>'creditAmount','')::numeric,0);
    v_ledger_id:=nullif(v_item->>'ledgerId','')::uuid;
    v_subject_entity_id:=nullif(v_item->>'subjectEntityId','')::uuid;
    insert into atlas.accounting_journal_lines(
      journal_entry_id,line_ordinal,accounting_account_id,debit_amount,credit_amount,memo,
      ledger_id,subject_entity_id,dimensions,metadata
    ) values (
      v_entry.id,v_ordinal,v_account_id,v_debit,v_credit,
      nullif(btrim(coalesce(v_item->>'memo','')),''),v_ledger_id,v_subject_entity_id,
      coalesce(v_item->'dimensions','{}'::jsonb),coalesce(v_item->'metadata','{}'::jsonb)
    );
  end loop;

  return jsonb_build_object(
    'contractVersion','accounting_journal_draft_v1','state',case when v_existing.id is null then 'created' else 'replaced' end,
    'journalEntryId',v_entry.id,'accountingBookId',v_entry.accounting_book_id,'entryDate',v_entry.entry_date,
    'entryKind',v_entry.entry_kind,'entryState',v_entry.entry_state,
    'balance',atlas.accounting_entry_balance_core_v1(v_entry.id),
    'truthBoundary',jsonb_build_object('canonicalAccountingMutation',false,'draftOnly',true)
  );
end;
$$;

revoke all on function atlas.replace_accounting_journal_draft_self_api_v1(uuid,text,date,text,text,jsonb,jsonb,jsonb,uuid)
  from public,anon;
grant execute on function atlas.replace_accounting_journal_draft_self_api_v1(uuid,text,date,text,text,jsonb,jsonb,jsonb,uuid)
  to authenticated;

create or replace function atlas.post_accounting_journal_entry_self_api_v1(p_journal_entry_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare
  v_entry atlas.accounting_journal_entries%rowtype;
  v_balance jsonb;
  v_principal_id uuid;
  v_period atlas.accounting_periods%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  select * into v_entry from atlas.accounting_journal_entries where id=p_journal_entry_id for update;
  if v_entry.id is null then raise exception 'Accounting journal entry not found.' using errcode='23503'; end if;
  if not atlas.accounting_book_authorized_self_v1(v_entry.accounting_book_id) then
    raise exception 'Accounting book authority required.' using errcode='42501';
  end if;
  if v_entry.entry_state='posted' then
    return jsonb_build_object('contractVersion','accounting_journal_post_v1','state','unchanged','journalEntryId',v_entry.id,'entryState','posted');
  end if;
  if v_entry.entry_state<>'draft' then raise exception 'Only draft accounting entries may be posted.' using errcode='55000'; end if;

  select * into v_period from atlas.accounting_periods p
  where p.accounting_book_id=v_entry.accounting_book_id
    and v_entry.entry_date between p.period_start_on and p.period_end_on
  limit 1;
  if v_period.id is null then raise exception 'An accounting period covering the entry date is required.' using errcode='23503'; end if;
  if v_period.period_state<>'open' then raise exception 'The accounting period is not open for posting.' using errcode='55000'; end if;

  v_balance:=atlas.accounting_entry_balance_core_v1(v_entry.id);
  if coalesce((v_balance->>'balanced')::boolean,false) is not true then
    raise exception 'A journal entry must have at least two lines and equal positive debits and credits before posting.' using errcode='23514';
  end if;
  if exists(
    select 1 from atlas.accounting_journal_lines line
    join atlas.accounting_accounts account on account.id=line.accounting_account_id
    where line.journal_entry_id=v_entry.id and account.account_state<>'active'
  ) then raise exception 'Every account on a posted entry must be active.' using errcode='55000'; end if;

  v_principal_id:=atlas.current_principal_id_v1();
  if v_principal_id is null then raise exception 'Principal context required.' using errcode='42501'; end if;

  update atlas.accounting_journal_entries
  set entry_state='posted',posted_by_principal_id=v_principal_id,posted_by_user_id=auth.uid(),posted_at=now(),updated_at=now()
  where id=v_entry.id returning * into v_entry;

  return jsonb_build_object(
    'contractVersion','accounting_journal_post_v1','state','posted','journalEntryId',v_entry.id,
    'accountingBookId',v_entry.accounting_book_id,'entryDate',v_entry.entry_date,'postedAt',v_entry.posted_at,
    'balance',v_balance,'truthBoundary',jsonb_build_object('postedEntryImmutable',true,'correctionRequiresNewEntry',true)
  );
end;
$$;

revoke all on function atlas.post_accounting_journal_entry_self_api_v1(uuid) from public,anon;
grant execute on function atlas.post_accounting_journal_entry_self_api_v1(uuid) to authenticated;

create or replace function atlas.reverse_accounting_journal_entry_self_api_v1(
  p_journal_entry_id uuid,
  p_reversal_date date,
  p_client_entry_key text,
  p_memo text default null
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare
  v_original atlas.accounting_journal_entries%rowtype;
  v_lines jsonb;
  v_draft jsonb;
  v_reversal_id uuid;
begin
  select * into v_original from atlas.accounting_journal_entries where id=p_journal_entry_id;
  if v_original.id is null or v_original.entry_state<>'posted' then
    raise exception 'A posted accounting journal entry is required for reversal.' using errcode='23503';
  end if;
  if not atlas.accounting_book_authorized_self_v1(v_original.accounting_book_id) then
    raise exception 'Accounting book authority required.' using errcode='42501';
  end if;
  if p_reversal_date is null then raise exception 'Reversal date required.' using errcode='22023'; end if;

  if exists(select 1 from atlas.accounting_journal_entries e where e.reversal_of_entry_id=v_original.id and e.entry_state='posted') then
    select e.id into v_reversal_id from atlas.accounting_journal_entries e
    where e.reversal_of_entry_id=v_original.id and e.entry_state='posted' limit 1;
    return jsonb_build_object('contractVersion','accounting_journal_reversal_v1','state','unchanged','originalEntryId',v_original.id,'reversalEntryId',v_reversal_id);
  end if;

  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'accountingAccountId',line.accounting_account_id,
    'debitAmount',line.credit_amount,
    'creditAmount',line.debit_amount,
    'memo',coalesce(nullif(btrim(coalesce(p_memo,'')),''),'Reversal of '||v_original.client_entry_key),
    'ledgerId',line.ledger_id,
    'subjectEntityId',line.subject_entity_id,
    'dimensions',line.dimensions,
    'metadata',jsonb_build_object('reversesJournalLineId',line.id)
  )) order by line.line_ordinal)
  into v_lines
  from atlas.accounting_journal_lines line where line.journal_entry_id=v_original.id;

  v_draft:=atlas.replace_accounting_journal_draft_self_api_v1(
    v_original.accounting_book_id,p_client_entry_key,p_reversal_date,'reversal',
    coalesce(nullif(btrim(coalesce(p_memo,'')),''),'Reversal of '||v_original.client_entry_key),v_lines,
    jsonb_build_object('authority','reverse_accounting_journal_entry_self_api_v1','reversalOfEntryId',v_original.id),
    '{}'::jsonb,v_original.id
  );
  v_reversal_id:=(v_draft->>'journalEntryId')::uuid;
  perform atlas.post_accounting_journal_entry_self_api_v1(v_reversal_id);

  return jsonb_build_object(
    'contractVersion','accounting_journal_reversal_v1','state','posted',
    'originalEntryId',v_original.id,'reversalEntryId',v_reversal_id,'reversalDate',p_reversal_date,
    'truthBoundary',jsonb_build_object('originalEntryPreserved',true,'reversalIsSeparatePostedEntry',true)
  );
end;
$$;

revoke all on function atlas.reverse_accounting_journal_entry_self_api_v1(uuid,date,text,text) from public,anon;
grant execute on function atlas.reverse_accounting_journal_entry_self_api_v1(uuid,date,text,text) to authenticated;

create or replace function atlas.cancel_accounting_journal_draft_self_api_v1(p_journal_entry_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare v_entry atlas.accounting_journal_entries%rowtype;
begin
  select * into v_entry from atlas.accounting_journal_entries where id=p_journal_entry_id for update;
  if v_entry.id is null then raise exception 'Accounting journal entry not found.' using errcode='23503'; end if;
  if not atlas.accounting_book_authorized_self_v1(v_entry.accounting_book_id) then raise exception 'Accounting book authority required.' using errcode='42501'; end if;
  if v_entry.entry_state='cancelled' then return jsonb_build_object('state','unchanged','journalEntryId',v_entry.id,'entryState','cancelled'); end if;
  if v_entry.entry_state<>'draft' then raise exception 'Only a draft accounting entry may be cancelled.' using errcode='55000'; end if;
  update atlas.accounting_journal_entries set entry_state='cancelled',cancelled_at=now(),updated_at=now() where id=v_entry.id returning * into v_entry;
  return jsonb_build_object('contractVersion','accounting_journal_cancel_v1','state','cancelled','journalEntryId',v_entry.id,'entryState',v_entry.entry_state);
end;
$$;

revoke all on function atlas.cancel_accounting_journal_draft_self_api_v1(uuid) from public,anon;
grant execute on function atlas.cancel_accounting_journal_draft_self_api_v1(uuid) to authenticated;

create or replace function atlas.close_accounting_period_self_api_v1(p_accounting_period_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare v_period atlas.accounting_periods%rowtype;
begin
  select * into v_period from atlas.accounting_periods where id=p_accounting_period_id for update;
  if v_period.id is null then raise exception 'Accounting period not found.' using errcode='23503'; end if;
  if not atlas.accounting_book_authorized_self_v1(v_period.accounting_book_id) then raise exception 'Accounting book authority required.' using errcode='42501'; end if;
  if v_period.period_state='locked' then raise exception 'Locked accounting period cannot be changed.' using errcode='55000'; end if;
  if v_period.period_state='closed' then return jsonb_build_object('contractVersion','accounting_period_close_v1','state','unchanged','accountingPeriodId',v_period.id,'periodState','closed'); end if;
  if exists(
    select 1 from atlas.accounting_journal_entries e
    where e.accounting_book_id=v_period.accounting_book_id
      and e.entry_date between v_period.period_start_on and v_period.period_end_on
      and e.entry_state='draft'
  ) then raise exception 'Accounting period cannot close while journal drafts remain in the period.' using errcode='55000'; end if;
  update atlas.accounting_periods set period_state='closed',closed_at=now(),closed_by_user_id=auth.uid(),updated_at=now()
  where id=v_period.id returning * into v_period;
  return jsonb_build_object('contractVersion','accounting_period_close_v1','state','closed','accountingPeriodId',v_period.id,'periodState',v_period.period_state,'closedAt',v_period.closed_at);
end;
$$;

revoke all on function atlas.close_accounting_period_self_api_v1(uuid) from public,anon;
grant execute on function atlas.close_accounting_period_self_api_v1(uuid) to authenticated;

create or replace function atlas.reopen_accounting_period_self_api_v1(p_accounting_period_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare v_period atlas.accounting_periods%rowtype;
begin
  select * into v_period from atlas.accounting_periods where id=p_accounting_period_id for update;
  if v_period.id is null then raise exception 'Accounting period not found.' using errcode='23503'; end if;
  if not atlas.accounting_book_authorized_self_v1(v_period.accounting_book_id) then raise exception 'Accounting book authority required.' using errcode='42501'; end if;
  if v_period.period_state='locked' then raise exception 'Locked accounting period cannot be reopened.' using errcode='55000'; end if;
  if v_period.period_state='open' then return jsonb_build_object('contractVersion','accounting_period_reopen_v1','state','unchanged','accountingPeriodId',v_period.id,'periodState','open'); end if;
  update atlas.accounting_periods set period_state='open',closed_at=null,closed_by_user_id=null,updated_at=now()
  where id=v_period.id returning * into v_period;
  return jsonb_build_object('contractVersion','accounting_period_reopen_v1','state','open','accountingPeriodId',v_period.id,'periodState',v_period.period_state);
end;
$$;

revoke all on function atlas.reopen_accounting_period_self_api_v1(uuid) from public,anon;
grant execute on function atlas.reopen_accounting_period_self_api_v1(uuid) to authenticated;

create or replace function atlas.lock_accounting_period_self_api_v1(p_accounting_period_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare v_period atlas.accounting_periods%rowtype;
begin
  select * into v_period from atlas.accounting_periods where id=p_accounting_period_id for update;
  if v_period.id is null then raise exception 'Accounting period not found.' using errcode='23503'; end if;
  if not atlas.accounting_book_authorized_self_v1(v_period.accounting_book_id) then raise exception 'Accounting book authority required.' using errcode='42501'; end if;
  if v_period.period_state='locked' then return jsonb_build_object('contractVersion','accounting_period_lock_v1','state','unchanged','accountingPeriodId',v_period.id,'periodState','locked'); end if;
  if v_period.period_state<>'closed' then raise exception 'Accounting period must be closed before it can be locked.' using errcode='55000'; end if;
  update atlas.accounting_periods set period_state='locked',locked_at=now(),locked_by_user_id=auth.uid(),updated_at=now()
  where id=v_period.id returning * into v_period;
  return jsonb_build_object('contractVersion','accounting_period_lock_v1','state','locked','accountingPeriodId',v_period.id,'periodState',v_period.period_state,'lockedAt',v_period.locked_at);
end;
$$;

revoke all on function atlas.lock_accounting_period_self_api_v1(uuid) from public,anon;
grant execute on function atlas.lock_accounting_period_self_api_v1(uuid) to authenticated;

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
      'ledgerId',scope.ledger_id,'ledgerName',l.display_name,'subjectEntityId',l.subject_entity_id,'scopeState',scope.scope_state
    ) order by l.display_name,scope.ledger_id)
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

revoke all on function atlas.accounting_book_self_api_v1(uuid) from public,anon;
grant execute on function atlas.accounting_book_self_api_v1(uuid) to authenticated;

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
           coalesce(sum(l.debit_amount),0) as debit_total,
           coalesce(sum(l.credit_amount),0) as credit_total
    from atlas.accounting_accounts a
    left join atlas.accounting_journal_lines l on l.accounting_account_id=a.id
    left join atlas.accounting_journal_entries e
      on e.id=l.journal_entry_id and e.entry_state='posted' and e.entry_date<=p_as_of_on
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

revoke all on function atlas.accounting_trial_balance_self_api_v1(uuid,date) from public,anon;
grant execute on function atlas.accounting_trial_balance_self_api_v1(uuid,date) to authenticated;

create or replace function atlas.accounting_journal_window_self_api_v1(
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
begin
  if not atlas.accounting_book_authorized_self_v1(p_accounting_book_id) then raise exception 'Accounting book authority required.' using errcode='42501'; end if;
  if p_start_on is null or p_end_on is null or p_end_on<p_start_on then raise exception 'Valid journal window required.' using errcode='22023'; end if;
  return jsonb_build_object(
    'contractVersion','accounting_journal_window_v1','accountingBookId',p_accounting_book_id,
    'startOn',p_start_on,'endOn',p_end_on,
    'entries',coalesce((
      select jsonb_agg(jsonb_build_object(
        'journalEntryId',e.id,'clientEntryKey',e.client_entry_key,'entryDate',e.entry_date,'entryKind',e.entry_kind,
        'entryState',e.entry_state,'memo',e.memo,'reversalOfEntryId',e.reversal_of_entry_id,'postedAt',e.posted_at,
        'balance',atlas.accounting_entry_balance_core_v1(e.id),
        'lines',coalesce((select jsonb_agg(jsonb_build_object(
          'journalLineId',l.id,'ordinal',l.line_ordinal,'accountingAccountId',l.accounting_account_id,
          'accountName',a.account_name,'debitAmount',l.debit_amount,'creditAmount',l.credit_amount,
          'memo',l.memo,'ledgerId',l.ledger_id,'subjectEntityId',l.subject_entity_id,'dimensions',l.dimensions
        ) order by l.line_ordinal)
          from atlas.accounting_journal_lines l join atlas.accounting_accounts a on a.id=l.accounting_account_id
          where l.journal_entry_id=e.id),'[]'::jsonb)
      ) order by e.entry_date,e.created_at,e.id)
      from atlas.accounting_journal_entries e
      where e.accounting_book_id=p_accounting_book_id and e.entry_date between p_start_on and p_end_on
    ),'[]'::jsonb),
    'truthBoundary',jsonb_build_object('readOnly',true,'includesDraftsAndPostedEntries',true)
  );
end;
$$;

revoke all on function atlas.accounting_journal_window_self_api_v1(uuid,date,date) from public,anon;
grant execute on function atlas.accounting_journal_window_self_api_v1(uuid,date,date) to authenticated;

comment on table atlas.accounting_books is
  'Accounting/reporting books downstream of Reality and operational Ledgers. A book chooses a reporting entity and included Ledger scopes but does not establish either.';
comment on table atlas.accounting_accounts is
  'Chart of Accounts for one accounting book. Categories and operational purposes may map here later but are not identical to accounts.';
comment on table atlas.accounting_journal_entries is
  'Double-entry accounting interpretations. Drafts are proposals; posted entries are immutable and corrections are separate reversal/adjusting entries.';
comment on table atlas.accounting_journal_lines is
  'Debit/credit lines for one accounting journal entry. Cross-line balance is enforced before draft save and again before posting.';
comment on table atlas.accounting_periods is
  'Non-overlapping accounting periods. Closed periods reject posting; locked periods cannot be reopened.';
comment on function atlas.accounting_trial_balance_self_api_v1(uuid,date) is
  'Read-only trial balance from posted journal entries through the requested date.';
