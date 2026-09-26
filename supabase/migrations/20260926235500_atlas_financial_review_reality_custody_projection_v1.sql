-- Carry canonical / claimed source custody into each financial review row.

create or replace function atlas.financial_review_self_api_v1(p_start_on date,p_end_on date)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth','reality'
as $function$
declare
  v_principal uuid:=atlas.current_principal_id_v1();
begin
  if auth.uid() is null or v_principal is null then raise exception 'Signed-in Principal required.' using errcode='42501'; end if;
  if p_start_on is null or p_end_on is null or p_end_on<p_start_on then raise exception 'Valid financial review window required.' using errcode='22023'; end if;

  return jsonb_build_object(
    'contractVersion','financial_review_self_v3',
    'startOn',p_start_on,
    'endOn',p_end_on,
    'items',coalesce((
      select jsonb_agg(jsonb_build_object(
        'transactionId',t.id,
        'source',jsonb_strip_nulls(jsonb_build_object(
          'sourceId',s.id,
          'accessCarrierKind',case when s.custodian_user_id is not null then 'human' else 'organization' end,
          'providerKey',s.provider_key,
          'providerAccountKey',s.provider_account_key,
          'displayLabel',s.display_label,
          'accountHint',s.account_hint,
          'capabilities',s.capabilities,
          'custodyState',s.custody_state,
          'claimedOwnerLabel',s.custody_claim_label,
          'custodianEntity',case when owner.id is null then null else jsonb_build_object(
            'id',owner.id,
            'stableKey',owner.stable_key,
            'kind',owner.entity_kind,
            'displayName',owner.display_name,
            'identityState',owner.identity_state
          ) end,
          'metadata',s.metadata
        )),
        'transactionDate',t.transaction_date,
        'postedAt',t.posted_at,
        'direction',t.direction,
        'amount',t.amount,
        'currency',t.currency,
        'description',t.description,
        'counterpartyLabel',t.counterparty_label,
        'sourceTransactionKind',t.source_transaction_kind,
        'truthState',t.truth_state,
        'evidenceRecordId',t.evidence_record_id,
        'confirmedTransferAmount',coalesce(x.transfer_amount,0),
        'commercialReconciliationAmount',coalesce(c.commercial_amount,0),
        'activeAllocationAmount',coalesce(a.allocation_amount,0)+coalesce(i.allocation_amount,0),
        'resolutionState',case
          when coalesce(x.transfer_amount,0)+coalesce(c.commercial_amount,0)+coalesce(a.allocation_amount,0)+coalesce(i.allocation_amount,0)=0 then 'unresolved'
          when coalesce(x.transfer_amount,0)+coalesce(c.commercial_amount,0)+coalesce(a.allocation_amount,0)+coalesce(i.allocation_amount,0)<t.amount then 'partial'
          else 'resolved' end,
        'transfers',coalesce(x.transfers,'[]'::jsonb),
        'commercialReconciliations',coalesce(c.reconciliations,'[]'::jsonb),
        'allocations',coalesce(a.allocations,'[]'::jsonb)||coalesce(i.allocations,'[]'::jsonb)
      ) order by t.transaction_date desc,t.id)
      from atlas.financial_source_transactions t
      join atlas.connected_sources s on s.id=t.connected_source_id
      left join reality.entities owner on owner.id=s.custodian_entity_id
      left join lateral (
        select sum(r.amount) as transfer_amount,
               jsonb_agg(jsonb_build_object(
                 'reconciliationId',r.id,
                 'fromTransactionId',r.from_transaction_id,
                 'toTransactionId',r.to_transaction_id,
                 'amount',r.amount,
                 'currency',r.currency,
                 'transferKind',r.transfer_kind,
                 'state',r.reconciliation_state
               ) order by r.created_at,r.id) as transfers
        from atlas.financial_transfer_reconciliations r
        where r.reconciliation_state='confirmed' and (r.from_transaction_id=t.id or r.to_transaction_id=t.id)
      ) x on true
      left join lateral (
        select sum(r.amount) as commercial_amount,
               jsonb_agg(jsonb_build_object(
                 'reconciliationId',r.id,
                 'commercialPaymentEventId',r.commercial_payment_event_id,
                 'amount',r.amount,
                 'currency',r.currency,
                 'state',r.reconciliation_state
               ) order by r.created_at,r.id) as reconciliations
        from atlas.financial_commercial_reconciliations r
        where r.financial_source_transaction_id=t.id and r.reconciliation_state='confirmed'
      ) c on true
      left join lateral (
        select sum(fa.allocated_amount) as allocation_amount,
               jsonb_agg(jsonb_build_object(
                 'allocationId',fa.id,
                 'allocationKind',fa.allocation_kind,
                 'amount',fa.allocated_amount,
                 'subjectDomain',fa.subject_domain,
                 'subjectKind',fa.subject_kind,
                 'subjectId',fa.subject_id,
                 'targetLedgerId',fa.target_ledger_id,
                 'targetOrganizationId',fa.target_organization_id,
                 'operationalPurpose',fa.operational_purpose,
                 'promotedSpendOccurrenceId',fa.promoted_spend_occurrence_id
               ) order by fa.created_at,fa.id) as allocations
        from atlas.financial_transaction_allocations fa
        where fa.transaction_id=t.id and fa.allocation_state='active'
      ) a on true
      left join lateral (
        select sum(fi.allocated_amount) as allocation_amount,
               jsonb_agg(jsonb_build_object(
                 'allocationId',fi.id,
                 'allocationKind',fi.allocation_kind,
                 'amount',fi.allocated_amount,
                 'receiptKind',fi.receipt_kind,
                 'targetLedgerId',fi.target_ledger_id,
                 'targetOrganizationId',fi.target_organization_id,
                 'operationalPurpose',fi.operational_purpose,
                 'receiptOccurrenceId',ro.id
               ) order by fi.created_at,fi.id) as allocations
        from atlas.financial_inflow_allocations fi
        left join atlas.organization_receipt_occurrences ro on ro.financial_inflow_allocation_id=fi.id
        where fi.transaction_id=t.id and fi.allocation_state='active'
      ) i on true
      where t.transaction_date between p_start_on and p_end_on
        and atlas.financial_source_authorized_self_v1(t.connected_source_id)
    ),'[]'::jsonb),
    'truthBoundary',jsonb_build_object(
      'accessCarrierIsNotCustody',true,
      'sourceCustodyIsNotPurpose',true,
      'transferIsNotExpenseOrIncome',true,
      'commercialReconciliationDoesNotDuplicateRevenue',true,
      'allocationRequiresHumanConfirmation',true,
      'organizationSpendPromotionIsSeparateFromSourceEvidence',true,
      'organizationReceiptIsNotCommercialOrderOrTaxTreatment',true
    )
  );
end;
$function$;

comment on function atlas.financial_review_self_api_v1(date,date) is
  'Principal financial review with canonical or explicitly unresolved Reality source custody carried beside immutable source transactions and human-confirmed dispositions.';