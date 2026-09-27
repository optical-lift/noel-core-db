-- Fundraising/accounting canonical identity bridge v1.
-- Accounting counterparty/subject dimensions use the same canonical Reality UUIDs as
-- Smart Contacts, fundraising relationships, and communication routes.

create or replace function atlas.guard_accounting_journal_line_canonical_subject_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if new.subject_entity_id is not null and not exists(
    select 1
    from reality.entities e
    where e.id=new.subject_entity_id
      and e.identity_state='canonical'
  ) then
    raise exception 'Accounting journal line subject must be a canonical Reality entity.' using errcode='23514';
  end if;
  return new;
end;
$$;

revoke all on function atlas.guard_accounting_journal_line_canonical_subject_v1()
  from public,anon,authenticated;

drop trigger if exists accounting_journal_line_canonical_subject_guard_v1
  on atlas.accounting_journal_lines;
create trigger accounting_journal_line_canonical_subject_guard_v1
before insert or update of subject_entity_id
on atlas.accounting_journal_lines
for each row execute function atlas.guard_accounting_journal_line_canonical_subject_v1();

comment on function atlas.guard_accounting_journal_line_canonical_subject_v1() is
  'Prevents accounting from creating a second counterparty identity universe. Journal subject_entity_id, when present, must resolve to canonical Reality.';

create or replace function atlas.fundraising_constituent_accounting_activity_self_api_v1(
  p_accounting_book_id uuid,
  p_constituent_entity_id uuid,
  p_start_on date,
  p_end_on date
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_reporting_entity_id uuid;
  v_constituent reality.entities%rowtype;
begin
  if not atlas.accounting_book_authorized_self_v1(p_accounting_book_id) then
    raise exception 'Accounting book authority required.' using errcode='42501';
  end if;
  if p_start_on is null or p_end_on is null or p_end_on<p_start_on then
    raise exception 'Valid constituent accounting date range required.' using errcode='22023';
  end if;

  select b.reporting_entity_id into v_reporting_entity_id
  from atlas.accounting_books b
  where b.id=p_accounting_book_id and b.book_state='active';
  if v_reporting_entity_id is null then
    raise exception 'Active accounting book not found.' using errcode='P0002';
  end if;

  select * into v_constituent
  from reality.entities e
  where e.id=p_constituent_entity_id and e.identity_state='canonical';
  if v_constituent.id is null then
    raise exception 'Canonical constituent Reality entity required.' using errcode='23503';
  end if;

  if not exists(
    select 1
    from atlas.fundraising_constituent_relationships r
    where r.fundraising_entity_id=v_reporting_entity_id
      and r.constituent_entity_id=p_constituent_entity_id
      and r.relationship_state='active'
      and r.ended_at is null
  ) then
    raise exception 'Constituent is not active for the accounting book reporting entity.' using errcode='23503';
  end if;

  return jsonb_build_object(
    'contractVersion','fundraising_constituent_accounting_activity_v1',
    'accountingBookId',p_accounting_book_id,
    'fundraisingEntityId',v_reporting_entity_id,
    'constituentEntityId',v_constituent.id,
    'displayName',v_constituent.display_name,
    'entityKind',v_constituent.entity_kind,
    'startOn',p_start_on,
    'endOn',p_end_on,
    'postedActivity',coalesce((
      select jsonb_agg(jsonb_build_object(
        'journalEntryId',entry.id,
        'entryDate',entry.entry_date,
        'entryKind',entry.entry_kind,
        'memo',entry.memo,
        'journalLineId',line.id,
        'lineOrdinal',line.line_ordinal,
        'accountingAccountId',account.id,
        'accountCode',account.account_code,
        'accountName',account.account_name,
        'accountClass',account.account_class,
        'debitAmount',line.debit_amount,
        'creditAmount',line.credit_amount,
        'ledgerId',line.ledger_id,
        'subjectEntityId',line.subject_entity_id,
        'dimensions',line.dimensions
      ) order by entry.entry_date,entry.id,line.line_ordinal),'[]'::jsonb)
      from atlas.accounting_journal_lines line
      join atlas.accounting_journal_entries entry
        on entry.id=line.journal_entry_id
       and entry.accounting_book_id=p_accounting_book_id
       and entry.entry_state='posted'
       and entry.entry_date between p_start_on and p_end_on
      join atlas.accounting_accounts account
        on account.id=line.accounting_account_id
       and account.accounting_book_id=p_accounting_book_id
      where line.subject_entity_id=p_constituent_entity_id
    ),
    'truthBoundary',jsonb_build_object(
      'sameRealityEntityAsSmartContactsAndFundraising',true,
      'postedEntriesOnly',true,
      'readOnly',true,
      'accountingDoesNotOwnConstituentIdentity',true
    )
  );
end;
$$;

revoke all on function atlas.fundraising_constituent_accounting_activity_self_api_v1(uuid,uuid,date,date)
  from public,anon;
grant execute on function atlas.fundraising_constituent_accounting_activity_self_api_v1(uuid,uuid,date,date)
  to authenticated;
