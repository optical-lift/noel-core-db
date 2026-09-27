-- Accounting financial-source posting bridge v1.
--
-- Reviewed source meaning may propose a balanced accounting draft, but review itself never posts
-- accounting truth. The source financial account is explicitly bound to a balance-sheet account.
-- Only narrow treatments with unambiguous first-order double-entry shapes are automated here.

create table if not exists atlas.accounting_financial_source_account_bindings (
  id uuid primary key default gen_random_uuid(),
  accounting_book_id uuid not null references atlas.accounting_books(id) on delete restrict,
  financial_source_account_id uuid not null references atlas.financial_source_accounts(id) on delete restrict,
  accounting_account_id uuid not null references atlas.accounting_accounts(id) on delete restrict,
  source_positive_posting_side text not null default 'debit',
  binding_state text not null default 'active',
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  bound_at timestamptz not null default now(),
  retired_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint accounting_financial_source_binding_side_check check (source_positive_posting_side in ('debit','credit')),
  constraint accounting_financial_source_binding_state_check check (binding_state in ('active','retired')),
  constraint accounting_financial_source_binding_retired_check check (
    (binding_state='active' and retired_at is null) or (binding_state='retired' and retired_at is not null)
  ),
  constraint accounting_financial_source_binding_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint accounting_financial_source_binding_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(accounting_book_id,financial_source_account_id)
);

create index if not exists accounting_financial_source_binding_account_idx
  on atlas.accounting_financial_source_account_bindings(financial_source_account_id,binding_state,accounting_book_id);

alter table atlas.accounting_financial_source_account_bindings enable row level security;
revoke all on table atlas.accounting_financial_source_account_bindings from public,anon,authenticated;

create or replace function atlas.guard_accounting_financial_source_binding_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $$
declare
  v_account atlas.accounting_accounts%rowtype;
begin
  select * into v_account from atlas.accounting_accounts account where account.id=new.accounting_account_id;
  if v_account.id is null or v_account.accounting_book_id<>new.accounting_book_id
     or v_account.account_state<>'active' or v_account.account_class not in ('asset','liability') then
    raise exception 'Financial source binding requires an active asset or liability account in the same book.' using errcode='23514';
  end if;
  new.updated_at:=now();
  return new;
end;
$$;

revoke all on function atlas.guard_accounting_financial_source_binding_v1() from public,anon,authenticated;
drop trigger if exists accounting_financial_source_binding_guard_v1 on atlas.accounting_financial_source_account_bindings;
create trigger accounting_financial_source_binding_guard_v1
before insert or update on atlas.accounting_financial_source_account_bindings
for each row execute function atlas.guard_accounting_financial_source_binding_v1();

create or replace function atlas.bind_accounting_financial_source_account_self_api_v1(
  p_accounting_book_id uuid,
  p_financial_source_account_id uuid,
  p_accounting_account_id uuid,
  p_source_positive_posting_side text default 'debit',
  p_provenance jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare
  v_side text:=lower(btrim(coalesce(p_source_positive_posting_side,'')));
  v_account atlas.accounting_accounts%rowtype;
  v_binding atlas.accounting_financial_source_account_bindings%rowtype;
begin
  if not atlas.accounting_book_authorized_self_v1(p_accounting_book_id) then
    raise exception 'Accounting book authority required.' using errcode='42501';
  end if;
  if not atlas.financial_source_account_authorized_self_v2(p_financial_source_account_id) then
    raise exception 'Financial source account authority required.' using errcode='42501';
  end if;
  if v_side not in ('debit','credit') then raise exception 'Source-positive posting side must be debit or credit.' using errcode='22023'; end if;
  if p_provenance is null or jsonb_typeof(p_provenance)<>'object'
     or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Binding provenance and metadata must be JSON objects.' using errcode='22023';
  end if;

  select * into v_account from atlas.accounting_accounts account
  where account.id=p_accounting_account_id
    and account.accounting_book_id=p_accounting_book_id
    and account.account_state='active'
    and account.account_class in ('asset','liability');
  if v_account.id is null then
    raise exception 'Financial source account must bind to an active asset or liability account in the same book.' using errcode='23503';
  end if;

  insert into atlas.accounting_financial_source_account_bindings(
    accounting_book_id,financial_source_account_id,accounting_account_id,source_positive_posting_side,
    binding_state,provenance,metadata
  ) values (
    p_accounting_book_id,p_financial_source_account_id,p_accounting_account_id,v_side,'active',
    p_provenance||jsonb_build_object(
      'authority','bind_accounting_financial_source_account_self_api_v1',
      'financialSourceIdentityIndependentOfChartAccount',true
    ),p_metadata
  ) on conflict(accounting_book_id,financial_source_account_id)
  do update set
    accounting_account_id=excluded.accounting_account_id,
    source_positive_posting_side=excluded.source_positive_posting_side,
    binding_state='active',retired_at=null,
    provenance=atlas.accounting_financial_source_account_bindings.provenance||excluded.provenance,
    metadata=atlas.accounting_financial_source_account_bindings.metadata||excluded.metadata,
    updated_at=now()
  returning * into v_binding;

  return jsonb_build_object(
    'contractVersion','accounting_financial_source_binding_v1',
    'bindingId',v_binding.id,'accountingBookId',v_binding.accounting_book_id,
    'financialSourceAccountId',v_binding.financial_source_account_id,
    'accountingAccountId',v_binding.accounting_account_id,
    'accountingAccountName',v_account.account_name,
    'sourcePositivePostingSide',v_binding.source_positive_posting_side,
    'bindingState',v_binding.binding_state,
    'truthBoundary',jsonb_build_object(
      'sourceAccountNotReplacedByChartAccount',true,
      'accountOwnershipDoesNotDetermineBook',true
    )
  );
end;
$$;

revoke all on function atlas.bind_accounting_financial_source_account_self_api_v1(uuid,uuid,uuid,text,jsonb,jsonb)
  from public,anon;
grant execute on function atlas.bind_accounting_financial_source_account_self_api_v1(uuid,uuid,uuid,text,jsonb,jsonb)
  to authenticated;

create or replace function atlas.propose_accounting_entry_from_financial_review_self_api_v1(
  p_accounting_book_id uuid,
  p_financial_transaction_id uuid,
  p_allocation_account_bindings jsonb,
  p_memo text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth,ledger
as $$
declare
  v_transaction atlas.financial_source_transactions%rowtype;
  v_review atlas.financial_source_transaction_review_events%rowtype;
  v_source_binding atlas.accounting_financial_source_account_bindings%rowtype;
  v_source_account atlas.accounting_accounts%rowtype;
  v_source_evidence_record_id uuid;
  v_eligible_count integer:=0;
  v_binding_count integer:=0;
  v_item jsonb;
  v_allocation atlas.financial_source_transaction_allocations%rowtype;
  v_target_account atlas.accounting_accounts%rowtype;
  v_allocation_id uuid;
  v_target_account_id uuid;
  v_seen_allocations uuid[]:='{}'::uuid[];
  v_lines jsonb:='[]'::jsonb;
  v_total numeric:=0;
  v_target_side text;
  v_source_side text;
  v_subject_entity_id uuid;
  v_client_key text;
  v_draft jsonb;
  v_entry_id uuid;
  v_old_entry_id uuid;
  v_posted_entry_id uuid;
begin
  if not atlas.accounting_book_authorized_self_v1(p_accounting_book_id) then
    raise exception 'Accounting book authority required.' using errcode='42501';
  end if;
  if p_allocation_account_bindings is null or jsonb_typeof(p_allocation_account_bindings)<>'array'
     or jsonb_array_length(p_allocation_account_bindings)>100 then
    raise exception 'Allocation/account bindings must be a JSON array of at most one hundred items.' using errcode='22023';
  end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then raise exception 'Proposal metadata must be a JSON object.' using errcode='22023'; end if;

  select * into v_transaction from atlas.financial_source_transactions transaction
  where transaction.id=p_financial_transaction_id
    and transaction.financial_source_account_id is not null
    and transaction.current_financial_evidence_observation_id is not null;
  if v_transaction.id is null then raise exception 'Account-centered financial transaction required.' using errcode='23503'; end if;
  if not atlas.financial_source_account_authorized_self_v2(v_transaction.financial_source_account_id) then
    raise exception 'Financial source account authority required.' using errcode='42501';
  end if;

  select * into v_review from atlas.financial_source_transaction_review_events review
  where review.financial_transaction_id=v_transaction.id
  order by review.review_revision desc limit 1;
  if v_review.id is null then raise exception 'Confirmed financial transaction review required.' using errcode='55000'; end if;
  if v_review.financial_evidence_observation_id is distinct from v_transaction.current_financial_evidence_observation_id then
    return jsonb_build_object(
      'contractVersion','accounting_financial_review_proposal_v1','state','requires_review',
      'financialTransactionId',v_transaction.id,'reviewEventId',v_review.id
    );
  end if;

  select * into v_source_binding
  from atlas.accounting_financial_source_account_bindings binding
  where binding.accounting_book_id=p_accounting_book_id
    and binding.financial_source_account_id=v_transaction.financial_source_account_id
    and binding.binding_state='active' and binding.retired_at is null;
  if v_source_binding.id is null then
    return jsonb_build_object(
      'contractVersion','accounting_financial_review_proposal_v1','state','source_account_binding_required',
      'financialTransactionId',v_transaction.id,'financialSourceAccountId',v_transaction.financial_source_account_id
    );
  end if;
  select * into v_source_account from atlas.accounting_accounts where id=v_source_binding.accounting_account_id;

  select count(*)::integer into v_eligible_count
  from atlas.financial_source_transaction_allocations allocation
  where allocation.review_event_id=v_review.id
    and allocation.treatment_kind in ('operating_expense','operating_revenue','owner_funding');

  if v_eligible_count=0 then
    return jsonb_build_object(
      'contractVersion','accounting_financial_review_proposal_v1','state','nothing_to_post',
      'financialTransactionId',v_transaction.id,'reviewEventId',v_review.id,
      'reason','Current review contains no v1 auto-postable accounting treatments.'
    );
  end if;
  if jsonb_array_length(p_allocation_account_bindings)<>v_eligible_count then
    raise exception 'Every auto-postable review allocation must map to exactly one accounting account.' using errcode='22023';
  end if;

  if v_transaction.source_amount<0 then
    v_target_side:='debit';
  else
    v_target_side:='credit';
  end if;
  v_source_side:=case
    when v_transaction.source_amount>0 then v_source_binding.source_positive_posting_side
    when v_source_binding.source_positive_posting_side='debit' then 'credit'
    else 'debit'
  end;
  if v_source_side=v_target_side then
    return jsonb_build_object(
      'contractVersion','accounting_financial_review_proposal_v1','state','source_orientation_conflict',
      'financialTransactionId',v_transaction.id,'sourcePositivePostingSide',v_source_binding.source_positive_posting_side,
      'sourceAmount',v_transaction.source_amount,'requiredTargetSide',v_target_side
    );
  end if;

  for v_item in select value from jsonb_array_elements(p_allocation_account_bindings)
  loop
    if jsonb_typeof(v_item)<>'object' then raise exception 'Every allocation/account binding must be an object.' using errcode='22023'; end if;
    begin
      v_allocation_id:=(v_item->>'allocationId')::uuid;
      v_target_account_id:=(v_item->>'accountingAccountId')::uuid;
    exception when others then
      raise exception 'Allocation and accounting account IDs must be UUIDs.' using errcode='22023';
    end;
    if v_allocation_id=any(v_seen_allocations) then raise exception 'Each review allocation may be mapped only once.' using errcode='22023'; end if;
    v_seen_allocations:=array_append(v_seen_allocations,v_allocation_id);

    select * into v_allocation from atlas.financial_source_transaction_allocations allocation
    where allocation.id=v_allocation_id and allocation.review_event_id=v_review.id
      and allocation.treatment_kind in ('operating_expense','operating_revenue','owner_funding');
    if v_allocation.id is null then raise exception 'Mapped allocation is not an auto-postable allocation in the current review.' using errcode='23503'; end if;

    if (v_transaction.source_amount<0 and v_allocation.treatment_kind<>'operating_expense')
       or (v_transaction.source_amount>0 and v_allocation.treatment_kind not in ('operating_revenue','owner_funding')) then
      raise exception 'Review treatment is inconsistent with source transaction direction.' using errcode='23514';
    end if;

    select * into v_target_account from atlas.accounting_accounts account
    where account.id=v_target_account_id
      and account.accounting_book_id=p_accounting_book_id
      and account.account_state='active';
    if v_target_account.id is null then raise exception 'Mapped accounting account must be active in this book.' using errcode='23503'; end if;
    if v_allocation.treatment_kind='operating_expense' and v_target_account.account_class<>'expense' then
      raise exception 'Operating expense allocations must map to expense accounts.' using errcode='22023';
    end if;
    if v_allocation.treatment_kind='operating_revenue' and v_target_account.account_class<>'revenue' then
      raise exception 'Operating revenue allocations must map to revenue accounts.' using errcode='22023';
    end if;
    if v_allocation.treatment_kind='owner_funding' and v_target_account.account_class<>'equity' then
      raise exception 'Owner funding allocations must map to equity accounts.' using errcode='22023';
    end if;

    v_subject_entity_id:=null;
    if v_allocation.target_ledger_id is not null then
      if not exists(
        select 1 from atlas.accounting_book_ledger_scopes scope
        where scope.accounting_book_id=p_accounting_book_id and scope.ledger_id=v_allocation.target_ledger_id
          and scope.scope_state='active' and scope.ended_at is null
      ) then raise exception 'Reviewed allocation Ledger is outside this accounting book.' using errcode='23503'; end if;
      select subject_entity_id into v_subject_entity_id from ledger.ledgers where id=v_allocation.target_ledger_id;
    end if;

    v_total:=v_total+v_allocation.allocated_amount;
    v_binding_count:=v_binding_count+1;
    v_lines:=v_lines||jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'accountingAccountId',v_target_account.id,
      'debitAmount',case when v_target_side='debit' then v_allocation.allocated_amount else 0 end,
      'creditAmount',case when v_target_side='credit' then v_allocation.allocated_amount else 0 end,
      'memo',coalesce(v_allocation.operational_purpose,v_transaction.source_party_label,v_transaction.raw_description),
      'ledgerId',v_allocation.target_ledger_id,
      'subjectEntityId',v_subject_entity_id,
      'dimensions',jsonb_build_object(
        'financialReviewEventId',v_review.id,
        'financialAllocationId',v_allocation.id,
        'treatmentKind',v_allocation.treatment_kind
      )
    )));
  end loop;

  if v_binding_count<>v_eligible_count or exists(
    select 1 from atlas.financial_source_transaction_allocations allocation
    where allocation.review_event_id=v_review.id
      and allocation.treatment_kind in ('operating_expense','operating_revenue','owner_funding')
      and not (allocation.id=any(v_seen_allocations))
  ) then
    raise exception 'Every auto-postable review allocation must be mapped exactly once.' using errcode='23514';
  end if;

  v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
    'accountingAccountId',v_source_account.id,
    'debitAmount',case when v_source_side='debit' then v_total else 0 end,
    'creditAmount',case when v_source_side='credit' then v_total else 0 end,
    'memo',coalesce(v_transaction.source_party_label,v_transaction.raw_description,'Financial source'),
    'dimensions',jsonb_build_object(
      'financialSourceAccountId',v_transaction.financial_source_account_id,
      'financialTransactionId',v_transaction.id
    )
  ));

  v_client_key:='financial-review:'||v_review.id::text||':book:'||p_accounting_book_id::text;

  -- A later review never silently rewrites a posted accounting entry.
  select entry.id into v_posted_entry_id
  from atlas.accounting_journal_entry_sources source
  join atlas.accounting_journal_entries entry on entry.id=source.journal_entry_id and entry.entry_state='posted'
  where source.source_domain='finance' and source.source_kind='financial_source_transaction'
    and source.source_id=v_transaction.id::text and entry.accounting_book_id=p_accounting_book_id
  order by entry.posted_at desc,entry.id desc limit 1;
  if v_posted_entry_id is not null and not exists(
    select 1 from atlas.accounting_journal_entry_sources source
    where source.journal_entry_id=v_posted_entry_id
      and source.source_domain='finance' and source.source_kind='financial_source_review'
      and source.source_id=v_review.id::text
  ) then
    return jsonb_build_object(
      'contractVersion','accounting_financial_review_proposal_v1','state','requires_accounting_correction',
      'financialTransactionId',v_transaction.id,'reviewEventId',v_review.id,'postedJournalEntryId',v_posted_entry_id
    );
  end if;
  if v_posted_entry_id is not null then
    return jsonb_build_object(
      'contractVersion','accounting_financial_review_proposal_v1','state','already_posted',
      'financialTransactionId',v_transaction.id,'reviewEventId',v_review.id,'journalEntryId',v_posted_entry_id
    );
  end if;

  -- Cancel any older unposted proposal for the same source transaction in this book.
  for v_old_entry_id in
    select distinct entry.id
    from atlas.accounting_journal_entry_sources source
    join atlas.accounting_journal_entries entry on entry.id=source.journal_entry_id and entry.entry_state='draft'
    where source.source_domain='finance' and source.source_kind='financial_source_transaction'
      and source.source_id=v_transaction.id::text and entry.accounting_book_id=p_accounting_book_id
      and entry.client_entry_key<>v_client_key
  loop
    perform atlas.cancel_accounting_journal_draft_self_api_v1(v_old_entry_id);
  end loop;

  v_draft:=atlas.replace_accounting_journal_draft_self_api_v1(
    p_accounting_book_id,v_client_key,v_transaction.occurred_on,'source_projection',
    coalesce(nullif(btrim(coalesce(p_memo,'')),''),coalesce(v_transaction.source_party_label,v_transaction.raw_description,'Financial transaction')),
    v_lines,
    jsonb_build_object(
      'authority','propose_accounting_entry_from_financial_review_self_api_v1',
      'financialTransactionId',v_transaction.id,
      'financialReviewEventId',v_review.id,
      'financialEvidenceObservationId',v_review.financial_evidence_observation_id,
      'sourceEvidenceIsUpstreamOfAccounting',true
    ),p_metadata,null
  );
  v_entry_id:=(v_draft->>'journalEntryId')::uuid;

  select observation.evidence_record_id into v_source_evidence_record_id
  from atlas.financial_source_evidence_observations observation
  where observation.id=v_review.financial_evidence_observation_id;

  insert into atlas.accounting_journal_entry_sources(
    journal_entry_id,source_domain,source_kind,source_id,relation_kind,evidence_record_id,provenance
  ) values (
    v_entry_id,'finance','financial_source_transaction',v_transaction.id::text,'basis',v_source_evidence_record_id,
    jsonb_build_object('authority','propose_accounting_entry_from_financial_review_self_api_v1')
  ) on conflict do nothing;
  insert into atlas.accounting_journal_entry_sources(
    journal_entry_id,source_domain,source_kind,source_id,relation_kind,provenance
  ) values (
    v_entry_id,'finance','financial_source_review',v_review.id::text,'interpretation',
    jsonb_build_object('authority','propose_accounting_entry_from_financial_review_self_api_v1')
  ) on conflict do nothing;

  for v_allocation_id in select unnest(v_seen_allocations)
  loop
    insert into atlas.accounting_journal_entry_sources(
      journal_entry_id,source_domain,source_kind,source_id,relation_kind,provenance
    ) values (
      v_entry_id,'finance','financial_source_allocation',v_allocation_id::text,'allocation',
      jsonb_build_object('authority','propose_accounting_entry_from_financial_review_self_api_v1')
    ) on conflict do nothing;
  end loop;

  return jsonb_build_object(
    'contractVersion','accounting_financial_review_proposal_v1','state','draft_ready',
    'financialTransactionId',v_transaction.id,'reviewEventId',v_review.id,
    'journalEntryId',v_entry_id,'accountingBookId',p_accounting_book_id,
    'postingAmount',v_total,'currency',v_transaction.currency,
    'balance',atlas.accounting_entry_balance_core_v1(v_entry_id),
    'truthBoundary',jsonb_build_object(
      'financialReviewDoesNotPostAccounting',true,
      'journalRemainsDraftUntilExplicitPost',true,
      'unsupportedTreatmentsNotAutoPosted',true
    )
  );
end;
$$;

revoke all on function atlas.propose_accounting_entry_from_financial_review_self_api_v1(uuid,uuid,jsonb,text,jsonb)
  from public,anon;
grant execute on function atlas.propose_accounting_entry_from_financial_review_self_api_v1(uuid,uuid,jsonb,text,jsonb)
  to authenticated;

create or replace function atlas.accounting_financial_source_bindings_self_api_v1(p_accounting_book_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $$
begin
  if not atlas.accounting_book_authorized_self_v1(p_accounting_book_id) then raise exception 'Accounting book authority required.' using errcode='42501'; end if;
  return jsonb_build_object(
    'contractVersion','accounting_financial_source_bindings_v1','accountingBookId',p_accounting_book_id,
    'bindings',coalesce((select jsonb_agg(jsonb_build_object(
      'bindingId',binding.id,'financialSourceAccountId',binding.financial_source_account_id,
      'sourceDisplayLabel',source.display_label,'sourceAccountHint',source.account_hint,'sourceAccountKind',source.account_kind,
      'accountingAccountId',account.id,'accountingAccountName',account.account_name,'accountingAccountClass',account.account_class,
      'sourcePositivePostingSide',binding.source_positive_posting_side,'bindingState',binding.binding_state
    ) order by source.display_label nulls last,account.account_name,binding.id)
      from atlas.accounting_financial_source_account_bindings binding
      join atlas.financial_source_accounts source on source.id=binding.financial_source_account_id
      join atlas.accounting_accounts account on account.id=binding.accounting_account_id
      where binding.accounting_book_id=p_accounting_book_id),'[]'::jsonb),
    'truthBoundary',jsonb_build_object('bindingMapsBalanceSheetPostingAccountOnly',true,'doesNotEstablishSourceOwnership',true)
  );
end;
$$;

revoke all on function atlas.accounting_financial_source_bindings_self_api_v1(uuid) from public,anon;
grant execute on function atlas.accounting_financial_source_bindings_self_api_v1(uuid) to authenticated;

comment on table atlas.accounting_financial_source_account_bindings is
  'Maps one canonical financial source account to its balance-sheet posting account inside one accounting book. The mapping does not change source identity or ownership.';
comment on function atlas.propose_accounting_entry_from_financial_review_self_api_v1(uuid,uuid,jsonb,text,jsonb) is
  'Builds a balanced accounting draft from the current reviewed financial transaction for supported treatments. It never posts the entry.';
