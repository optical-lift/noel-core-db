-- Hardening for the financial-source review membrane.
-- Keep source observations neutral; only observed source facts may be reconciled
-- or promoted, and transfer candidates remain structural suggestions only.

create or replace function atlas.confirm_financial_transfer_self_api_v1(
  p_from_transaction_id uuid,
  p_to_transaction_id uuid,
  p_amount numeric,
  p_transfer_kind text,
  p_client_event_key text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_principal uuid:=atlas.current_principal_id_v1();
  v_from atlas.financial_source_transactions%rowtype;
  v_to atlas.financial_source_transactions%rowtype;
  v_key text:=btrim(coalesce(p_client_event_key,''));
  v_kind text:=lower(btrim(coalesce(p_transfer_kind,'')));
  v_existing atlas.financial_transfer_reconciliations%rowtype;
  v_from_used numeric;
  v_to_used numeric;
  v_id uuid;
begin
  if auth.uid() is null or v_principal is null then raise exception 'Signed-in Principal required.' using errcode='42501'; end if;
  if v_key='' or p_amount is null or p_amount<=0 then raise exception 'Client event key and positive transfer amount are required.' using errcode='22023'; end if;
  if v_kind not in ('internal_transfer','liability_payment','owner_contribution','owner_draw','reimbursement','other') then raise exception 'Unsupported transfer kind.' using errcode='22023'; end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then raise exception 'Transfer metadata must be an object.' using errcode='22023'; end if;

  select * into v_existing from atlas.financial_transfer_reconciliations r
  where r.confirmed_by_principal_id=v_principal and r.client_event_key=v_key;
  if v_existing.id is not null then
    if v_existing.from_transaction_id is distinct from p_from_transaction_id
       or v_existing.to_transaction_id is distinct from p_to_transaction_id
       or v_existing.amount is distinct from p_amount
       or v_existing.transfer_kind is distinct from v_kind then
      raise exception 'Client event key already belongs to a different transfer confirmation.' using errcode='23514';
    end if;
    return jsonb_build_object('contractVersion','confirm_financial_transfer_self_api_v1','state','unchanged','reconciliationId',v_existing.id);
  end if;

  select * into v_from from atlas.financial_source_transactions where id=p_from_transaction_id for update;
  select * into v_to from atlas.financial_source_transactions where id=p_to_transaction_id for update;
  if v_from.id is null or v_to.id is null then raise exception 'Both source transactions are required.' using errcode='P0002'; end if;
  if v_from.truth_state<>'observed' or v_to.truth_state<>'observed' then raise exception 'Only observed, undisputed source transactions may be reconciled.' using errcode='55000'; end if;
  if not atlas.financial_source_authorized_self_v1(v_from.connected_source_id)
     or not atlas.financial_source_authorized_self_v1(v_to.connected_source_id) then
    raise exception 'Source custody required for both sides of a transfer.' using errcode='42501';
  end if;
  if v_from.direction<>'debit' or v_to.direction<>'credit' then raise exception 'A transfer must reconcile a debit source transaction to a credit source transaction.' using errcode='23514'; end if;
  if v_from.currency<>v_to.currency then raise exception 'Transfer sides must use the same currency.' using errcode='23514'; end if;
  if v_from.connected_source_id=v_to.connected_source_id then raise exception 'Transfer sides must belong to different financial sources.' using errcode='23514'; end if;

  select coalesce(sum(r.amount),0)
       + coalesce((select sum(a.allocated_amount) from atlas.financial_transaction_allocations a where a.transaction_id=v_from.id and a.allocation_state='active'),0)
  into v_from_used
  from atlas.financial_transfer_reconciliations r
  where r.from_transaction_id=v_from.id and r.reconciliation_state='confirmed';

  select coalesce(sum(r.amount),0) into v_to_used
  from atlas.financial_transfer_reconciliations r
  where r.to_transaction_id=v_to.id and r.reconciliation_state='confirmed';

  if v_from_used+p_amount>v_from.amount or v_to_used+p_amount>v_to.amount then
    raise exception 'Transfer amount exceeds the unreconciled source amount.' using errcode='23514';
  end if;

  insert into atlas.financial_transfer_reconciliations(
    from_transaction_id,to_transaction_id,amount,currency,transfer_kind,
    confirmed_by_principal_id,client_event_key,metadata
  ) values(
    v_from.id,v_to.id,p_amount,v_from.currency,v_kind,v_principal,v_key,p_metadata
  ) returning id into v_id;

  return jsonb_build_object(
    'contractVersion','confirm_financial_transfer_self_api_v1',
    'state','confirmed','reconciliationId',v_id,
    'truthBoundary',jsonb_build_object(
      'expenseCreated',false,'incomeCreated',false,'sourceEvidenceMutated',false,
      'transferMeaningHumanConfirmed',true
    )
  );
end;
$function$;

create or replace function atlas.financial_transfer_candidates_self_api_v1(
  p_start_on date,
  p_end_on date,
  p_max_day_distance integer default 3
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_principal uuid:=atlas.current_principal_id_v1();
begin
  if auth.uid() is null or v_principal is null then raise exception 'Signed-in Principal required.' using errcode='42501'; end if;
  if p_start_on is null or p_end_on is null or p_end_on<p_start_on then raise exception 'Valid transfer-candidate window required.' using errcode='22023'; end if;
  if p_max_day_distance is null or p_max_day_distance<0 or p_max_day_distance>14 then raise exception 'Transfer candidate day distance must be between 0 and 14.' using errcode='22023'; end if;

  return jsonb_build_object(
    'contractVersion','financial_transfer_candidates_self_v1',
    'startOn',p_start_on,'endOn',p_end_on,'maxDayDistance',p_max_day_distance,
    'items',coalesce((
      with debit_remaining as (
        select d.*,
          d.amount
          - coalesce((select sum(r.amount) from atlas.financial_transfer_reconciliations r where r.from_transaction_id=d.id and r.reconciliation_state='confirmed'),0)
          - coalesce((select sum(a.allocated_amount) from atlas.financial_transaction_allocations a where a.transaction_id=d.id and a.allocation_state='active'),0) as remaining_amount
        from atlas.financial_source_transactions d
        where d.direction='debit' and d.truth_state='observed'
          and d.transaction_date between p_start_on and p_end_on
          and atlas.financial_source_authorized_self_v1(d.connected_source_id)
      ),
      credit_remaining as (
        select c.*,
          c.amount
          - coalesce((select sum(r.amount) from atlas.financial_transfer_reconciliations r where r.to_transaction_id=c.id and r.reconciliation_state='confirmed'),0) as remaining_amount
        from atlas.financial_source_transactions c
        where c.direction='credit' and c.truth_state='observed'
          and c.transaction_date between p_start_on-p_max_day_distance and p_end_on+p_max_day_distance
          and atlas.financial_source_authorized_self_v1(c.connected_source_id)
      )
      select jsonb_agg(jsonb_build_object(
        'fromTransactionId',d.id,'toTransactionId',c.id,
        'amount',d.remaining_amount,'currency',d.currency,
        'dayDistance',abs(d.transaction_date-c.transaction_date),
        'fromDate',d.transaction_date,'toDate',c.transaction_date,
        'fromDescription',d.description,'toDescription',c.description,
        'fromSource',jsonb_build_object('sourceId',ds.id,'displayLabel',ds.display_label,'accountHint',ds.account_hint,'providerKey',ds.provider_key),
        'toSource',jsonb_build_object('sourceId',cs.id,'displayLabel',cs.display_label,'accountHint',cs.account_hint,'providerKey',cs.provider_key),
        'basis',jsonb_build_object('sameRemainingAmount',true,'sameCurrency',true,'differentSource',true,'nearbyDate',true)
      ) order by abs(d.transaction_date-c.transaction_date),d.transaction_date,d.id,c.id)
      from debit_remaining d
      join credit_remaining c
        on c.currency=d.currency
       and c.remaining_amount=d.remaining_amount
       and c.remaining_amount>0
       and c.connected_source_id<>d.connected_source_id
       and abs(d.transaction_date-c.transaction_date)<=p_max_day_distance
      join atlas.connected_sources ds on ds.id=d.connected_source_id
      join atlas.connected_sources cs on cs.id=c.connected_source_id
      where d.remaining_amount>0
    ),'[]'::jsonb),
    'truthBoundary',jsonb_build_object(
      'suggestionOnly',true,
      'noTransferKindInferred',true,
      'noReconciliationWritten',true,
      'merchantTextNotUsedAsAuthority',true
    )
  );
end;
$function$;

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
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_principal uuid:=atlas.current_principal_id_v1();
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
  if auth.uid() is null or v_principal is null then raise exception 'Signed-in Principal required.' using errcode='42501'; end if;
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
  if not atlas.financial_source_authorized_self_v1(v_tx.connected_source_id) then raise exception 'Financial source custody required.' using errcode='42501'; end if;
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
      v_funding_kind:=case
        when v_source.custodian_organization_id=v_organization_id then 'organization'
        when v_source.custodian_user_id=auth.uid() then 'organization_member'
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
          'financialSourceTransactionId',v_tx.id,'financialAllocationId',v_allocation_id,
          'connectedSourceId',v_tx.connected_source_id,'evidenceRecordId',v_tx.evidence_record_id
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
    'contractVersion','replace_financial_transaction_allocations_self_api_v1','state','replaced',
    'eventId',v_event.id,'transactionId',v_tx.id,'afterState',v_after,
    'truthBoundary',jsonb_build_object(
      'sourceEvidenceMutated',false,
      'transferAmountsExcludedFromSpend',true,
      'organizationSpendCreatedOnlyForConfirmedBusinessAllocations',true,
      'nonbusinessAllocationsDoNotCreateOrganizationSpend',true
    )
  );
end;
$function$;

revoke all on function atlas.financial_transfer_candidates_self_api_v1(date,date,integer) from public,anon,service_role;
grant execute on function atlas.financial_transfer_candidates_self_api_v1(date,date,integer) to authenticated;

comment on function atlas.financial_transfer_candidates_self_api_v1(date,date,integer) is
  'Read-only structural transfer candidates: exact remaining amount, same currency, different source, nearby date. No transfer kind or accounting meaning is inferred.';