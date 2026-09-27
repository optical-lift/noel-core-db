-- Accounting journal trigger/proposal hardening v1.

create or replace function atlas.guard_accounting_journal_line_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $$
declare
  v_entry_id uuid;
  v_entry_book uuid;
  v_entry_state text;
  v_account_book uuid;
  v_account_state text;
  v_ledger_allowed boolean;
begin
  v_entry_id:=case when tg_op='DELETE' then old.journal_entry_id else new.journal_entry_id end;
  select e.accounting_book_id,e.entry_state into v_entry_book,v_entry_state
  from atlas.accounting_journal_entries e where e.id=v_entry_id;
  if v_entry_book is null then raise exception 'Accounting journal entry not found.' using errcode='23503'; end if;
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
      where s.accounting_book_id=v_entry_book and s.ledger_id=new.ledger_id
        and s.scope_state='active' and s.ended_at is null
    ) into v_ledger_allowed;
    if not v_ledger_allowed then raise exception 'Journal line Ledger must be in the accounting book scope.' using errcode='23514'; end if;
  end if;
  return new;
end;
$$;

-- A cancelled proposal is a deliberate accounting decision. The deterministic review key remains
-- occupied; a new review revision is required before Atlas may propose a new accounting draft.
create or replace function atlas.accounting_financial_review_existing_proposal_state_v1(
  p_accounting_book_id uuid,
  p_review_event_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog,atlas
as $$
  select coalesce((
    select jsonb_build_object(
      'journalEntryId',entry.id,
      'entryState',entry.entry_state,
      'clientEntryKey',entry.client_entry_key,
      'entryDate',entry.entry_date
    )
    from atlas.accounting_journal_entry_sources source
    join atlas.accounting_journal_entries entry on entry.id=source.journal_entry_id
    where source.source_domain='finance'
      and source.source_kind='financial_source_review'
      and source.source_id=p_review_event_id::text
      and entry.accounting_book_id=p_accounting_book_id
    order by entry.created_at desc,entry.id desc
    limit 1
  ),'{}'::jsonb);
$$;

revoke all on function atlas.accounting_financial_review_existing_proposal_state_v1(uuid,uuid)
  from public,anon,authenticated,service_role;

comment on function atlas.accounting_financial_review_existing_proposal_state_v1(uuid,uuid) is
  'Internal read helper used to keep deterministic financial-review accounting proposals from silently resurrecting cancelled drafts.';
