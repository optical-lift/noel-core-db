-- Financial-review accounting proposal hardening v2.
-- Keep v1 as the internal builder; authenticated callers use v2 so a cancelled deterministic
-- proposal remains cancelled until a new financial review revision exists.

revoke all on function atlas.propose_accounting_entry_from_financial_review_self_api_v1(uuid,uuid,jsonb,text,jsonb)
  from authenticated;

create or replace function atlas.propose_accounting_entry_from_financial_review_self_api_v2(
  p_accounting_book_id uuid,
  p_financial_transaction_id uuid,
  p_allocation_account_bindings jsonb,
  p_memo text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare
  v_review atlas.financial_source_transaction_review_events%rowtype;
  v_existing jsonb;
  v_result jsonb;
begin
  if not atlas.accounting_book_authorized_self_v1(p_accounting_book_id) then
    raise exception 'Accounting book authority required.' using errcode='42501';
  end if;

  select * into v_review
  from atlas.financial_source_transaction_review_events review
  where review.financial_transaction_id=p_financial_transaction_id
  order by review.review_revision desc
  limit 1;
  if v_review.id is null then
    raise exception 'Confirmed financial transaction review required.' using errcode='55000';
  end if;

  v_existing:=atlas.accounting_financial_review_existing_proposal_state_v1(
    p_accounting_book_id,v_review.id
  );
  if coalesce(v_existing->>'entryState','')='cancelled' then
    return jsonb_build_object(
      'contractVersion','accounting_financial_review_proposal_v2',
      'state','proposal_cancelled',
      'financialTransactionId',p_financial_transaction_id,
      'reviewEventId',v_review.id,
      'journalEntryId',v_existing->>'journalEntryId',
      'reason','A cancelled proposal is not silently recreated. Create a new financial review revision before proposing accounting again.'
    );
  end if;

  v_result:=atlas.propose_accounting_entry_from_financial_review_self_api_v1(
    p_accounting_book_id,p_financial_transaction_id,p_allocation_account_bindings,p_memo,p_metadata
  );
  return jsonb_build_object(
    'contractVersion','accounting_financial_review_proposal_v2',
    'result',v_result,
    'state',coalesce(v_result->>'state','unknown')
  );
end;
$$;

revoke all on function atlas.propose_accounting_entry_from_financial_review_self_api_v2(uuid,uuid,jsonb,text,jsonb)
  from public,anon;
grant execute on function atlas.propose_accounting_entry_from_financial_review_self_api_v2(uuid,uuid,jsonb,text,jsonb)
  to authenticated;

comment on function atlas.propose_accounting_entry_from_financial_review_self_api_v2(uuid,uuid,jsonb,text,jsonb) is
  'Authenticated accounting proposal membrane. Delegates to the v1 draft builder but preserves explicit cancellation until a new financial review revision is created.';
