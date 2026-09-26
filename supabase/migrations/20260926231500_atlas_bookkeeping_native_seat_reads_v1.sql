-- Bring the bookkeeping read membrane onto the native Reality/Ledger seat model.
-- The legacy Principal-Ledger authority rows remain compatibility carriers only.

create or replace function atlas.organization_expense_reporting_root_principal_v1(p_ledger_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_principal uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required.' using errcode='42501';
  end if;
  v_principal:=atlas.current_principal_id_v1();
  if v_principal is null then
    raise exception 'Principal binding required.' using errcode='42501';
  end if;
  perform atlas.current_active_ledger_seat_v1(p_ledger_id);
  return v_principal;
end;
$function$;

create or replace function atlas.commercial_financial_position_self_api_v1(p_ledger_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_principal_id uuid;
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required.' using errcode='42501';
  end if;

  v_principal_id:=atlas.current_principal_id_v1();
  if v_principal_id is null then
    raise exception 'Principal binding required.' using errcode='42501';
  end if;
  perform atlas.current_active_ledger_seat_v1(p_ledger_id);

  select jsonb_build_object(
    'ledgerId',p_ledger_id,
    'orders',coalesce(jsonb_agg(jsonb_build_object(
      'commercialOrderId',p.commercial_order_id,
      'sourceDomain',p.source_domain,
      'sourceKind',p.source_kind,
      'sourceId',p.source_id,
      'orderKind',p.order_kind,
      'orderDate',p.order_date,
      'currency',p.currency,
      'committedAmount',p.committed_amount,
      'grossCollectedAmount',p.gross_collected_amount,
      'returnedAmount',p.returned_amount,
      'netCollectedAmount',p.net_collected_amount,
      'openAmount',p.open_amount,
      'overpaidAmount',p.overpaid_amount,
      'financialState',p.financial_state,
      'financialCoverage',p.financial_coverage,
      'financialCoverageBasis',p.financial_coverage_basis,
      'firstCollectionAt',p.first_collection_at,
      'lastCollectionAt',p.last_collection_at,
      'endedOrRefundedAt',p.ended_or_refunded_at,
      'custodyDisposition',p.custody_disposition,
      'custodyEvidenceBasis',p.custody_evidence_basis
    ) order by p.order_date desc,p.created_at desc,p.commercial_order_id),'[]'::jsonb)
  ) into v_result
  from atlas.commercial_financial_position_v1 p
  where p.effective_ledger_id=p_ledger_id;

  return v_result;
end;
$function$;

create or replace function atlas.organization_spend_window_self_api_v1(
  p_ledger_id uuid,
  p_start_on date,
  p_end_on date
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  perform atlas.current_active_ledger_seat_v1(p_ledger_id);
  if p_start_on is null or p_end_on is null or p_end_on<p_start_on then raise exception 'Valid Spend date window required.' using errcode='22023'; end if;

  return jsonb_build_object(
    'schemaVersion','atlas_organization_spend_window_v1',
    'ledgerId',p_ledger_id,
    'startOn',p_start_on,
    'endOn',p_end_on,
    'spend',coalesce((
      select jsonb_agg(jsonb_build_object(
        'spendOccurrenceId',p.spend_occurrence_id,
        'organizationId',p.organization_id,
        'organizationUnitId',p.organization_unit_id,
        'occurredOn',p.occurred_on,
        'occurredAt',p.occurred_at,
        'grossAmount',p.gross_amount,
        'currency',p.currency,
        'fundingKind',p.funding_kind,
        'payerMembershipId',p.payer_membership_id,
        'payeeExternalRelationshipId',p.payee_external_relationship_id,
        'payeeLabel',p.payee_label,
        'paymentMethod',p.payment_method,
        'truthState',p.truth_state,
        'allocatedAmount',p.allocated_amount,
        'unallocatedAmount',p.unallocated_amount,
        'activeAllocationCount',p.active_allocation_count,
        'allocations',coalesce((
          select jsonb_agg(jsonb_build_object(
            'id',a.id,
            'organizationUnitId',a.organization_unit_id,
            'amount',a.allocated_amount,
            'operationalPurpose',a.operational_purpose,
            'subjectDomain',a.subject_domain,
            'subjectKind',a.subject_kind,
            'subjectId',a.subject_id
          ) order by a.created_at,a.id)
          from atlas.organization_spend_allocations a
          where a.spend_occurrence_id=p.spend_occurrence_id and a.allocation_state='active'
        ),'[]'::jsonb)
      ) order by p.occurred_on desc,p.created_at desc,p.spend_occurrence_id)
      from atlas.organization_spend_position_v1 p
      where p.ledger_id=p_ledger_id
        and p.occurred_on between p_start_on and p_end_on
    ),'[]'::jsonb),
    'truthBoundary',jsonb_build_object(
      'authorizedByNativeLedgerSeat',true,
      'legacyPrincipalLedgerAuthorityRequired',false
    )
  );
end;
$function$;

comment on function atlas.organization_expense_reporting_root_principal_v1(uuid) is
  'Resolves the signed-in Principal only after native active Ledger-seat participation; legacy Principal-Ledger authority is not canonical.';
comment on function atlas.commercial_financial_position_self_api_v1(uuid) is
  'Reads commercial financial position for a native Ledger seat. The legacy Principal-Ledger authority carrier is not used as access authority.';
comment on function atlas.organization_spend_window_self_api_v1(uuid,date,date) is
  'Reads governed Organization Spend for a native Ledger seat. The legacy Principal-Ledger authority carrier is not used as access authority.';