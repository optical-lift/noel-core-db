-- Spend promotion must derive funding identity from canonical source custody,
-- never from the legacy connected-source access carrier.

create or replace function atlas.replace_financial_transaction_allocations_self_api_v1(
  p_transaction_id uuid,
  p_client_event_key text,
  p_allocations jsonb,
  p_reason text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth','ledger'
as $function$
declare
  v_principal uuid:=atlas.current_principal_id_v1();
  v_person uuid:=atlas.current_person_id_v1();
  v_tx atlas.financial_source_transactions%rowtype;
  v_source atlas.connected_sources%rowtype;
  v_key text:=btrim(coalesce(p_client_event_key,''));
  v_event atlas.financial_transaction_allocation_events%rowtype;
  v_item jsonb;
  v_kind text;
  v_amount numeric;
  v_total numeric:=0;
  v_transfer_amount numeric:=0;
  v_subject_domain text;
  v_subject_kind text;
  v_subject_id text;
  v_ledger_id uuid;
  v_organization_id uuid;
  v_target_entity_id uuid;
  v_purpose text;
  v_item_metadata jsonb;
  v_membership uuid;
  v_funding_kind text;
  v_allocation_id uuid;
  v_spend jsonb;
  v_spend_id uuid;
  v_spend_allocations jsonb;
  v_before jsonb;
  v_after jsonb;
begin
  if auth.uid() is null or v_principal is null or v_person is null then raise exception 'Signed-in Principal required.' using errcode='42501'; end if;
  if v_key='' or p_allocations is null or jsonb_typeof(p_allocations)<>'array' then raise exception 'Client event key and allocation array are required.' using errcode='22023'; end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then raise exception 'Allocation event metadata must be an object.' using errcode='22023'; end if;

  select * into v_event from atlas.financial_transaction_allocation_events e
  where e.actor_principal_id=v_principal and e.client_event_key=v_key;
  if v_event.id is not null then
    return jsonb_build_object('contractVersion','replace_financial_transaction_allocations_self_api_v1','state','unchanged','eventId',v_event.id,'afterState',v_event.after_state);
  end if;

  select * into v_tx from atlas.financial_source_transactions where id=p_transaction_id for update;
  if v_tx.id is null then raise exception 'Financial source transaction not found.' using errcode='P0002'; end if;
  if v_tx.truth_state<>'observed' then raise exception 'Only observed, undisputed source transactions may be allocated.' using errcode='55000'; end if;
  if not atlas.financial_source_authorized_self_v1(v_tx.connected_source_id) then raise exception 'Financial source access required.' using errcode='42501'; end if;
  if v_tx.direction<>'debit' then raise exception 'Expense-purpose allocations apply to debit source transactions only.' using errcode='23514'; end if;
  if exists(select 1 from atlas.financial_transaction_allocations a where a.transaction_id=v_tx.id and a.allocation_state='active' and a.promoted_spend_occurrence_id is not null) then
    raise exception 'A promoted business allocation cannot be silently replaced; correct the governed Spend instead.' using errcode='55000';
  end if;

  select * into v_source from atlas.connected_sources where id=v_tx.connected_source_id;
  select coalesce(sum(r.amount),0) into v_transfer_amount
  from atlas.financial_transfer_reconciliations r
  where r.from_transaction_id=v_tx.id and r.reconciliation_state='confirmed';

  for v_item in select value from jsonb_array_elements(p_allocations)
  loop
    if jsonb_typeof(v_item)<>'object' then raise exception 'Each financial allocation must be an object.' using errcode='22023'; end if;
    v_kind:=lower(btrim(coalesce(v_item->>'allocationKind','')));
    begin v_amount:=(v_item->>'amount')::numeric; exception when others then raise exception 'Each financial allocation requires numeric amount.' using errcode='22023'; end;
    if v_kind not in ('organization_spend','personal','household','nonbusiness','other') or v_amount is null or v_amount<=0 then raise exception 'Each financial allocation requires a supported kind and positive amount.' using errcode='22023'; end if;
    v_total:=v_total+v_amount;
    if v_kind='organization_spend' then
      begin
        v_ledger_id:=nullif(v_item->>'ledgerId','')::uuid;
        v_organization_id:=nullif(v_item->>'organizationId','')::uuid;
      exception when others then
        raise exception 'Business allocation Ledger and Organization IDs must be UUIDs.' using errcode='22023';
      end;
      if v_ledger_id is null or v_organization_id is null then raise exception 'Business allocation requires Ledger and Organization.' using errcode='22023'; end if;
      perform atlas.current_active_ledger_seat_v1(v_ledger_id);
      perform atlas.organization_spend_assert_custody_v1(v_ledger_id,v_organization_id);
      v_membership:=atlas.current_organization_membership_v1(v_organization_id);
      if v_membership is null then raise exception 'Organization membership required to promote business Spend.' using errcode='42501'; end if;
    end if;
  end loop;

  if v_transfer_amount+v_total>v_tx.amount then raise exception 'Transfer plus allocation amounts exceed the source transaction amount.' using errcode='23514'; end if;

  v_before:=atlas.financial_transaction_allocation_snapshot_v1(v_tx.id);
  insert into atlas.financial_transaction_allocation_events(
    transaction_id,actor_principal_id,event_kind,client_event_key,reason,before_state,metadata
  ) values(
    v_tx.id,v_principal,'allocations_replaced',v_key,nullif(btrim(coalesce(p_reason,'')),''),v_before,p_metadata
  ) returning * into v_event;

  update atlas.financial_transaction_allocations
  set allocation_state='superseded',superseded_at=now(),superseded_by_event_id=v_event.id
  where transaction_id=v_tx.id and allocation_state='active';

  for v_item in select value from jsonb_array_elements(p_allocations)
  loop
    v_kind:=lower(btrim(v_item->>'allocationKind'));
    v_amount:=(v_item->>'amount')::numeric;
    v_subject_domain:=nullif(btrim(coalesce(v_item->>'subjectDomain','')),'');
    v_subject_kind:=nullif(btrim(coalesce(v_item->>'subjectKind','')),'');
    v_subject_id:=nullif(btrim(coalesce(v_item->>'subjectId','')),'');
    v_purpose:=nullif(btrim(coalesce(v_item->>'operationalPurpose','')),'');
    v_item_metadata:=coalesce(v_item->'metadata','{}'::jsonb);
    if jsonb_typeof(v_item_metadata)<>'object' then raise exception 'Financial allocation metadata must be an object.' using errcode='22023'; end if;
    if (v_subject_domain is null or v_subject_kind is null or v_subject_id is null)
       and not (v_subject_domain is null and v_subject_kind is null and v_subject_id is null) then
      raise exception 'Allocation subject coordinates must be complete or omitted.' using errcode='22023';
    end if;

    v_ledger_id:=null;
    v_organization_id:=null;
    if v_kind='organization_spend' then
      v_ledger_id:=nullif(v_item->>'ledgerId','')::uuid;
      v_organization_id:=nullif(v_item->>'organizationId','')::uuid;
    end if;

    insert into atlas.financial_transaction_allocations(
      transaction_id,established_by_event_id,allocation_kind,allocated_amount,
      subject_domain,subject_kind,subject_id,target_ledger_id,target_organization_id,
      operational_purpose,confirmed_by_principal_id,metadata
    ) values(
      v_tx.id,v_event.id,v_kind,v_amount,
      v_subject_domain,v_subject_kind,v_subject_id,v_ledger_id,v_organization_id,
      v_purpose,v_principal,v_item_metadata
    ) returning id into v_allocation_id;

    if v_kind='organization_spend' then
      v_membership:=atlas.current_organization_membership_v1(v_organization_id);
      select l.subject_entity_id into v_target_entity_id
      from ledger.ledgers l
      where l.id=v_ledger_id and l.ledger_state='active' and l.retired_at is null;
      if v_target_entity_id is null then raise exception 'Active native Ledger subject required.' using errcode='23503'; end if;

      v_funding_kind:=case
        when v_source.custody_state='canonical' and v_source.custodian_entity_id=v_target_entity_id then 'organization'
        when v_source.custody_state='canonical' and v_source.custodian_entity_id=v_person then 'organization_member'
        when v_source.custody_state in ('claimed_unresolved','legacy_unresolved') then 'unresolved'
        else 'external_party'
      end;

      v_spend_allocations:=case when v_purpose is not null or v_subject_domain is not null then
        jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
          'amount',v_amount,'operationalPurpose',v_purpose,
          'subjectDomain',v_subject_domain,'subjectKind',v_subject_kind,'subjectId',v_subject_id
        ))) else null end;

      v_spend:=atlas.record_organization_spend_core_v1(
        v_ledger_id,v_organization_id,v_principal,v_membership,null,
        v_tx.transaction_date,v_tx.posted_at,v_amount,v_tx.currency,
        v_funding_kind,case when v_funding_kind='organization_member' then v_membership else null end,
        null,coalesce(v_tx.counterparty_label,v_tx.description),coalesce(v_source.display_label,v_source.provider_key),
        'financial_source_transaction',v_allocation_id::text,v_spend_allocations,
        jsonb_build_object(
          'financialSourceTransactionId',v_tx.id,
          'financialAllocationId',v_allocation_id,
          'connectedSourceId',v_tx.connected_source_id,
          'evidenceRecordId',v_tx.evidence_record_id,
          'sourceCustodyState',v_source.custody_state,
          'sourceCustodianEntityId',v_source.custodian_entity_id,
          'sourceCustodyClaimLabel',v_source.custody_claim_label,
          'fundingKindDerivedFromRealityCustody',true
        ),
        jsonb_build_object('promotedFromFinancialReview',true)
      );
      v_spend_id:=nullif(v_spend->>'spendOccurrenceId','')::uuid;
      perform atlas.link_organization_spend_evidence_core_v1(
        v_ledger_id,v_organization_id,v_spend_id,null,v_tx.evidence_record_id,
        'transaction_observation',v_principal,v_membership,
        jsonb_build_object('financialAllocationId',v_allocation_id)
      );
      update atlas.financial_transaction_allocations
      set promoted_spend_occurrence_id=v_spend_id
      where id=v_allocation_id;
    end if;
  end loop;

  v_after:=atlas.financial_transaction_allocation_snapshot_v1(v_tx.id);
  update atlas.financial_transaction_allocation_events set after_state=v_after where id=v_event.id;

  return jsonb_build_object(
    'contractVersion','replace_financial_transaction_allocations_self_api_v1',
    'state','replaced',
    'eventId',v_event.id,
    'transactionId',v_tx.id,
    'afterState',v_after,
    'truthBoundary',jsonb_build_object(
      'sourceEvidenceMutated',false,
      'transferAmountsExcludedFromSpend',true,
      'organizationSpendCreatedOnlyForConfirmedBusinessAllocations',true,
      'nonbusinessAllocationsDoNotCreateOrganizationSpend',true,
      'fundingKindUsesRealityCustodyNotAccessCarrier',true,
      'unresolvedSourceCustodyRemainsUnresolvedFunding',true
    )
  );
end;
$function$;

comment on function atlas.replace_financial_transaction_allocations_self_api_v1(uuid,text,jsonb,text,jsonb) is
  'Principal-confirmed debit allocation. Organization Spend funding kind is derived from canonical Reality source custody; unresolved source ownership remains unresolved rather than being inferred from the signed-in access carrier.';