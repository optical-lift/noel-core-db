-- Atlas account-centered financial transaction review + Spend promotion v2
--
-- Reviews bind to the exact current financial evidence observation. Spend promotion remains
-- separate and uses canonical Ledger subject for operational meaning. Account ownership may
-- inform funding provenance but cross-entity ownership fails closed as unresolved unless a
-- later governed reporting/funding relationship says otherwise.

alter table atlas.financial_source_transaction_review_events
  add column if not exists financial_evidence_observation_id uuid
    references atlas.financial_source_evidence_observations(id) on delete restrict;

alter table atlas.financial_source_transaction_review_events
  alter column source_observation_id drop not null;

alter table atlas.financial_source_transaction_review_events
  add constraint financial_source_transaction_review_evidence_path_check
  check (source_observation_id is not null or financial_evidence_observation_id is not null);

create index if not exists financial_source_transaction_review_evidence_idx
  on atlas.financial_source_transaction_review_events(financial_evidence_observation_id,review_revision desc)
  where financial_evidence_observation_id is not null;

create or replace function atlas.replace_financial_source_transaction_review_self_api_v2(
  p_financial_transaction_id uuid,
  p_client_event_key text,
  p_allocations jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth,extensions
as $$
declare
  v_transaction atlas.financial_source_transactions%rowtype;
  v_principal_id uuid;
  v_event_key text:=btrim(coalesce(p_client_event_key,''));
  v_allocations jsonb:=coalesce(p_allocations,'[]'::jsonb);
  v_input_hash text;
  v_existing_event atlas.financial_source_transaction_review_events%rowtype;
  v_review atlas.financial_source_transaction_review_events%rowtype;
  v_item jsonb;
  v_ordinal integer:=0;
  v_amount numeric;
  v_total numeric:=0;
  v_treatment text;
  v_target_ledger_id uuid;
  v_domain text;
  v_kind text;
  v_subject_id text;
  v_unresolved_count integer:=0;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if v_event_key='' or jsonb_typeof(v_allocations)<>'array'
     or jsonb_array_length(v_allocations)=0 or jsonb_array_length(v_allocations)>50 then
    raise exception 'Client event key and one to fifty review allocations are required.' using errcode='22023';
  end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Review metadata must be a JSON object.' using errcode='22023';
  end if;

  select * into v_transaction
  from atlas.financial_source_transactions transaction
  where transaction.id=p_financial_transaction_id
  for update;
  if v_transaction.id is null or v_transaction.financial_source_account_id is null
     or v_transaction.current_financial_evidence_observation_id is null then
    raise exception 'Account-centered financial source transaction not found.' using errcode='23503';
  end if;
  if not atlas.financial_source_account_authorized_self_v2(v_transaction.financial_source_account_id) then
    raise exception 'Financial source account authority required.' using errcode='42501';
  end if;

  v_principal_id:=atlas.current_principal_id_v1();
  if v_principal_id is null then raise exception 'Principal context required.' using errcode='42501'; end if;

  v_input_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'financialEvidenceObservationId',v_transaction.current_financial_evidence_observation_id,
    'allocations',v_allocations,'metadata',p_metadata
  )::text,'utf8'),'sha256'),'hex');

  select * into v_existing_event
  from atlas.financial_source_transaction_review_events review
  where review.financial_transaction_id=p_financial_transaction_id
    and review.client_event_key=v_event_key;
  if v_existing_event.id is not null then
    if v_existing_event.input_sha256<>v_input_hash then
      raise exception 'Financial transaction review event key was reused with different content.' using errcode='23514';
    end if;
    return jsonb_build_object(
      'contractVersion','replace_financial_source_transaction_review_self_api_v2',
      'state','unchanged','financialTransactionId',p_financial_transaction_id,
      'reviewEventId',v_existing_event.id,
      'financialEvidenceObservationId',v_existing_event.financial_evidence_observation_id
    );
  end if;

  for v_item in select value from jsonb_array_elements(v_allocations)
  loop
    if jsonb_typeof(v_item)<>'object' then
      raise exception 'Each financial transaction review allocation must be an object.' using errcode='22023';
    end if;
    begin v_amount:=(v_item->>'amount')::numeric;
    exception when others then raise exception 'Each review allocation requires a numeric amount.' using errcode='22023'; end;
    if v_amount is null or v_amount<=0 then
      raise exception 'Each review allocation amount must be greater than zero.' using errcode='22023';
    end if;

    v_treatment:=btrim(coalesce(v_item->>'treatmentKind',''));
    if v_treatment not in (
      'operating_expense','operating_revenue','owner_funding','transfer',
      'personal','refund_adjustment','unresolved'
    ) then
      raise exception 'Unsupported financial transaction treatment kind.' using errcode='22023';
    end if;

    begin v_target_ledger_id:=nullif(v_item->>'targetLedgerId','')::uuid;
    exception when others then raise exception 'Review allocation targetLedgerId must be a UUID.' using errcode='22023'; end;

    if v_treatment in ('operating_expense','operating_revenue') and v_target_ledger_id is null then
      raise exception 'Operating expense and revenue allocations require a target Ledger.' using errcode='22023';
    end if;
    if v_treatment='operating_expense' and v_transaction.source_amount>=0 then
      raise exception 'An operating expense allocation requires a source outflow.' using errcode='22023';
    end if;
    if v_treatment='operating_revenue' and v_transaction.source_amount<=0 then
      raise exception 'An operating revenue allocation requires a source inflow.' using errcode='22023';
    end if;
    if v_treatment='owner_funding' and v_transaction.source_amount<=0 then
      raise exception 'Owner funding requires a source inflow.' using errcode='22023';
    end if;

    if v_target_ledger_id is not null then
      perform atlas.current_active_ledger_seat_v1(v_target_ledger_id);
      if not atlas.principal_has_ledger_authority_v1(v_principal_id,v_target_ledger_id) then
        raise exception 'Target Ledger authority required.' using errcode='42501';
      end if;
    end if;

    v_domain:=nullif(btrim(coalesce(v_item->>'subjectDomain','')),'');
    v_kind:=nullif(btrim(coalesce(v_item->>'subjectKind','')),'');
    v_subject_id:=nullif(btrim(coalesce(v_item->>'subjectId','')),'');
    if not ((v_domain is null and v_kind is null and v_subject_id is null)
            or (v_domain is not null and v_kind is not null and v_subject_id is not null)) then
      raise exception 'Review allocation subjectDomain, subjectKind, and subjectId must be supplied together.' using errcode='22023';
    end if;

    v_total:=v_total+v_amount;
    if v_treatment='unresolved' then v_unresolved_count:=v_unresolved_count+1; end if;
  end loop;

  if v_total<>abs(v_transaction.source_amount) then
    raise exception 'Confirmed review allocations must account for the full absolute source amount.' using errcode='23514';
  end if;

  insert into atlas.financial_source_transaction_review_events(
    financial_transaction_id,source_observation_id,financial_evidence_observation_id,
    client_event_key,input_sha256,reviewed_by_principal_id,reviewed_by_user_id,review_basis,metadata
  ) values (
    p_financial_transaction_id,null,v_transaction.current_financial_evidence_observation_id,
    v_event_key,v_input_hash,v_principal_id,auth.uid(),
    jsonb_build_object(
      'authority','replace_financial_source_transaction_review_self_api_v2',
      'fullAmountAccounted',true,
      'sourceEvidencePreservedOutsideReview',true
    ),p_metadata
  ) returning * into v_review;

  v_ordinal:=0;
  for v_item in select value from jsonb_array_elements(v_allocations)
  loop
    v_ordinal:=v_ordinal+1;
    v_amount:=(v_item->>'amount')::numeric;
    v_treatment:=btrim(v_item->>'treatmentKind');
    v_target_ledger_id:=nullif(v_item->>'targetLedgerId','')::uuid;

    insert into atlas.financial_source_transaction_allocations(
      review_event_id,allocation_ordinal,treatment_kind,allocated_amount,target_ledger_id,
      operational_purpose,subject_domain,subject_kind,subject_id,metadata
    ) values (
      v_review.id,v_ordinal,v_treatment,v_amount,v_target_ledger_id,
      nullif(btrim(coalesce(v_item->>'operationalPurpose','')),''),
      nullif(btrim(coalesce(v_item->>'subjectDomain','')),''),
      nullif(btrim(coalesce(v_item->>'subjectKind','')),''),
      nullif(btrim(coalesce(v_item->>'subjectId','')),''),
      case when jsonb_typeof(coalesce(v_item->'metadata','{}'::jsonb))='object'
        then coalesce(v_item->'metadata','{}'::jsonb) else '{}'::jsonb end
    );
  end loop;

  return jsonb_build_object(
    'contractVersion','replace_financial_source_transaction_review_self_api_v2',
    'state','confirmed','financialTransactionId',p_financial_transaction_id,
    'reviewEventId',v_review.id,'reviewRevision',v_review.review_revision,
    'financialEvidenceObservationId',v_review.financial_evidence_observation_id,
    'allocationCount',jsonb_array_length(v_allocations),
    'unresolvedAllocationCount',v_unresolved_count,'fullyAccounted',true
  );
end;
$$;

revoke all on function atlas.replace_financial_source_transaction_review_self_api_v2(uuid,text,jsonb,jsonb)
  from public,anon;
grant execute on function atlas.replace_financial_source_transaction_review_self_api_v2(uuid,text,jsonb,jsonb)
  to authenticated;

create or replace function atlas.financial_source_transaction_review_window_self_api_v2(
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
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if p_start_on is null or p_end_on is null or p_end_on<p_start_on then
    raise exception 'A valid financial transaction review date window is required.' using errcode='22023';
  end if;

  return jsonb_build_object(
    'contractVersion','financial_source_transaction_review_window_v2',
    'startOn',p_start_on,'endOn',p_end_on,
    'items',coalesce((
      select jsonb_agg(jsonb_build_object(
        'financialTransactionId',transaction.id,
        'financialSourceAccountId',transaction.financial_source_account_id,
        'providerTransactionKey',transaction.provider_transaction_key,
        'currentFinancialEvidenceObservationId',transaction.current_financial_evidence_observation_id,
        'occurredOn',transaction.occurred_on,'occurredAt',transaction.occurred_at,
        'sourceAmount',transaction.source_amount,'currency',transaction.currency,
        'direction',case when transaction.source_amount<0 then 'outflow' else 'inflow' end,
        'rawDescription',transaction.raw_description,'sourcePartyLabel',transaction.source_party_label,
        'transactionState',transaction.transaction_state,
        'review',case when review.id is null then null else jsonb_build_object(
          'reviewEventId',review.id,'reviewRevision',review.review_revision,
          'financialEvidenceObservationId',review.financial_evidence_observation_id,
          'current',review.financial_evidence_observation_id=transaction.current_financial_evidence_observation_id,
          'reviewedAt',review.created_at,'allocations',coalesce(review_allocations.items,'[]'::jsonb)
        ) end,
        'promotionCount',coalesce(promotions.promotion_count,0),
        'needsReview',review.id is null or review.financial_evidence_observation_id is distinct from transaction.current_financial_evidence_observation_id
      ) order by transaction.occurred_on,transaction.id)
      from atlas.financial_source_transactions transaction
      left join lateral (
        select r.* from atlas.financial_source_transaction_review_events r
        where r.financial_transaction_id=transaction.id
        order by r.review_revision desc limit 1
      ) review on true
      left join lateral (
        select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
          'allocationId',allocation.id,'ordinal',allocation.allocation_ordinal,
          'treatmentKind',allocation.treatment_kind,'amount',allocation.allocated_amount,
          'targetLedgerId',allocation.target_ledger_id,'operationalPurpose',allocation.operational_purpose,
          'subjectDomain',allocation.subject_domain,'subjectKind',allocation.subject_kind,'subjectId',allocation.subject_id
        )) order by allocation.allocation_ordinal) as items
        from atlas.financial_source_transaction_allocations allocation
        where allocation.review_event_id=review.id
      ) review_allocations on true
      left join lateral (
        select count(*)::integer as promotion_count
        from atlas.financial_source_transaction_spend_promotions promotion
        where promotion.financial_transaction_id=transaction.id
      ) promotions on true
      where transaction.financial_source_account_id is not null
        and transaction.occurred_on between p_start_on and p_end_on
        and atlas.financial_source_account_authorized_self_v2(transaction.financial_source_account_id)
    ),'[]'::jsonb),
    'truthBoundary',jsonb_build_object(
      'accountOwnershipDoesNotDetermineOperationalBeneficiary',true,
      'sourceEvidencePreservedOutsideReview',true,
      'reviewDoesNotRewriteSourceEvidence',true,
      'spendPromotionIsSeparate',true
    )
  );
end;
$$;

revoke all on function atlas.financial_source_transaction_review_window_self_api_v2(date,date)
  from public,anon;
grant execute on function atlas.financial_source_transaction_review_window_self_api_v2(date,date)
  to authenticated;

create or replace function atlas.promote_financial_source_transaction_expense_self_api_v2(
  p_financial_transaction_id uuid,
  p_target_ledger_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth,reality,ledger,compatibility
as $$
declare
  v_transaction atlas.financial_source_transactions%rowtype;
  v_canonical_ledger ledger.ledgers%rowtype;
  v_review atlas.financial_source_transaction_review_events%rowtype;
  v_existing atlas.financial_source_transaction_spend_promotions%rowtype;
  v_source_evidence_observation atlas.financial_source_evidence_observations%rowtype;
  v_principal_id uuid;
  v_person_id uuid;
  v_organization_id uuid;
  v_membership_id uuid;
  v_funding_kind text;
  v_funding_inference text;
  v_payer_membership_id uuid;
  v_amount numeric;
  v_allocations jsonb;
  v_spend jsonb;
  v_spend_occurrence_id uuid;
  v_ledger_evidence_record_id uuid;
  v_link_id uuid;
  v_holder_entity_ids jsonb:='[]'::jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;

  select * into v_transaction
  from atlas.financial_source_transactions transaction
  where transaction.id=p_financial_transaction_id
  for update;
  if v_transaction.id is null or v_transaction.financial_source_account_id is null
     or v_transaction.current_financial_evidence_observation_id is null then
    raise exception 'Account-centered financial source transaction not found.' using errcode='23503';
  end if;
  if v_transaction.source_amount>=0 then
    raise exception 'Only source outflows may be promoted as Spend.' using errcode='22023';
  end if;
  if not atlas.financial_source_account_authorized_self_v2(v_transaction.financial_source_account_id) then
    raise exception 'Financial source account authority required.' using errcode='42501';
  end if;

  select * into v_canonical_ledger
  from ledger.ledgers canonical_ledger
  where canonical_ledger.id=p_target_ledger_id
    and canonical_ledger.ledger_state='active' and canonical_ledger.retired_at is null;
  if v_canonical_ledger.id is null then raise exception 'Active canonical Ledger required.' using errcode='23503'; end if;
  perform atlas.current_active_ledger_seat_v1(p_target_ledger_id);

  v_principal_id:=atlas.current_principal_id_v1();
  v_person_id:=atlas.current_person_id_v1();
  if v_principal_id is null or v_person_id is null then
    raise exception 'Reality Person and Principal context required.' using errcode='42501';
  end if;

  select participation.organization_id into v_organization_id
  from atlas.ledger_organization_participations participation
  join atlas.ledgers legacy_ledger on legacy_ledger.id=participation.ledger_id and legacy_ledger.status='active'
  join compatibility.legacy_bindings binding
    on binding.legacy_schema='atlas' and binding.legacy_table='organizations'
   and binding.legacy_key=participation.organization_id::text and binding.disposition='maps_to'
   and binding.new_schema='reality' and binding.new_table='entities'
   and binding.new_id=v_canonical_ledger.subject_entity_id
  where participation.ledger_id=p_target_ledger_id and participation.status='active'
  order by participation.created_at,participation.organization_id limit 1;

  if v_organization_id is null then
    return jsonb_build_object(
      'contractVersion','promote_financial_source_transaction_expense_self_api_v2',
      'state','compatibility_required','financialTransactionId',p_financial_transaction_id,
      'targetLedgerId',p_target_ledger_id,'ledgerSubjectEntityId',v_canonical_ledger.subject_entity_id,
      'reason','Package 5 organization routing carrier is unavailable for this canonical Ledger.'
    );
  end if;

  v_membership_id:=atlas.current_organization_membership_v1(v_organization_id);
  if v_membership_id is null then
    return jsonb_build_object(
      'contractVersion','promote_financial_source_transaction_expense_self_api_v2',
      'state','compatibility_required','financialTransactionId',p_financial_transaction_id,
      'targetLedgerId',p_target_ledger_id,'ledgerSubjectEntityId',v_canonical_ledger.subject_entity_id,
      'compatibilityOrganizationId',v_organization_id,
      'reason','Package 5 actor membership is unavailable for this canonical Ledger.'
    );
  end if;

  select * into v_review
  from atlas.financial_source_transaction_review_events review
  where review.financial_transaction_id=p_financial_transaction_id
  order by review.review_revision desc limit 1;
  if v_review.id is null then
    raise exception 'A confirmed financial transaction review is required before Spend promotion.' using errcode='55000';
  end if;
  if v_review.financial_evidence_observation_id is distinct from v_transaction.current_financial_evidence_observation_id then
    return jsonb_build_object(
      'contractVersion','promote_financial_source_transaction_expense_self_api_v2',
      'state','requires_review','financialTransactionId',p_financial_transaction_id,
      'reviewEventId',v_review.id,
      'reviewedFinancialEvidenceObservationId',v_review.financial_evidence_observation_id,
      'currentFinancialEvidenceObservationId',v_transaction.current_financial_evidence_observation_id
    );
  end if;

  select * into v_existing
  from atlas.financial_source_transaction_spend_promotions promotion
  where promotion.financial_transaction_id=p_financial_transaction_id
    and promotion.target_ledger_id=p_target_ledger_id;
  if v_existing.id is not null then
    if v_existing.review_event_id=v_review.id then
      return jsonb_build_object(
        'contractVersion','promote_financial_source_transaction_expense_self_api_v2',
        'state','unchanged','financialTransactionId',p_financial_transaction_id,
        'reviewEventId',v_review.id,'spendOccurrenceId',v_existing.spend_occurrence_id
      );
    end if;
    return jsonb_build_object(
      'contractVersion','promote_financial_source_transaction_expense_self_api_v2',
      'state','requires_correction','financialTransactionId',p_financial_transaction_id,
      'previousReviewEventId',v_existing.review_event_id,'currentReviewEventId',v_review.id,
      'spendOccurrenceId',v_existing.spend_occurrence_id
    );
  end if;

  select sum(allocation.allocated_amount),
         jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'amount',allocation.allocated_amount,'operationalPurpose',allocation.operational_purpose,
           'subjectDomain',allocation.subject_domain,'subjectKind',allocation.subject_kind,'subjectId',allocation.subject_id
         )) order by allocation.allocation_ordinal)
  into v_amount,v_allocations
  from atlas.financial_source_transaction_allocations allocation
  where allocation.review_event_id=v_review.id
    and allocation.treatment_kind='operating_expense'
    and allocation.target_ledger_id=p_target_ledger_id;
  if v_amount is null or v_amount<=0 then
    raise exception 'Current review has no operating expense allocation for the target Ledger.' using errcode='22023';
  end if;

  select coalesce(jsonb_agg(holder.holder_entity_id order by holder.holder_entity_id),'[]'::jsonb)
  into v_holder_entity_ids
  from atlas.financial_source_account_reality_holders holder
  where holder.financial_source_account_id=v_transaction.financial_source_account_id;

  if exists(
    select 1 from atlas.financial_source_account_reality_holders holder
    where holder.financial_source_account_id=v_transaction.financial_source_account_id
      and holder.holder_entity_id=v_canonical_ledger.subject_entity_id
  ) then
    v_funding_kind:='organization';
    v_funding_inference:='direct_ledger_subject_account_holder';
    v_payer_membership_id:=null;
  elsif exists(
    select 1 from atlas.financial_source_account_reality_holders holder
    where holder.financial_source_account_id=v_transaction.financial_source_account_id
      and holder.holder_entity_id=v_person_id
  ) then
    v_funding_kind:='organization_member';
    v_funding_inference:='current_person_account_holder';
    v_payer_membership_id:=v_membership_id;
  else
    v_funding_kind:='unresolved';
    v_funding_inference:=case when jsonb_array_length(v_holder_entity_ids)>0
      then 'cross_entity_account_holder_requires_governed_reporting_or_funding_relation'
      else 'account_holder_unresolved' end;
    v_payer_membership_id:=null;
  end if;

  v_spend:=atlas.record_organization_spend_core_v1(
    p_target_ledger_id,v_organization_id,v_principal_id,v_membership_id,null,
    v_transaction.occurred_on,v_transaction.occurred_at,v_amount,v_transaction.currency,
    v_funding_kind,v_payer_membership_id,null,
    coalesce(v_transaction.source_party_label,v_transaction.raw_description),
    'financial_source_account','financial_source_transaction',v_transaction.id::text,v_allocations,
    jsonb_build_object(
      'authority','promote_financial_source_transaction_expense_self_api_v2',
      'financialTransactionId',v_transaction.id,
      'financialSourceAccountId',v_transaction.financial_source_account_id,
      'financialEvidenceObservationId',v_transaction.current_financial_evidence_observation_id,
      'reviewEventId',v_review.id,'ledgerSubjectEntityId',v_canonical_ledger.subject_entity_id,
      'sourceAccountHolderEntityIds',v_holder_entity_ids,'fundingInference',v_funding_inference,
      'accountOwnershipIndependentOfOperationalTarget',true,'compatibilityOrganizationIsRoutingOnly',true
    ),
    jsonb_build_object(
      'importedFromFinancialSourceAccount',true,
      'providerTransactionKey',v_transaction.provider_transaction_key,
      'ledgerSubjectEntityId',v_canonical_ledger.subject_entity_id
    )
  );
  v_spend_occurrence_id:=(v_spend->>'spendOccurrenceId')::uuid;

  select * into v_source_evidence_observation
  from atlas.financial_source_evidence_observations observation
  where observation.id=v_transaction.current_financial_evidence_observation_id;
  if v_source_evidence_observation.id is null then
    raise exception 'Current financial evidence observation is unavailable.' using errcode='23503';
  end if;

  insert into atlas.evidence_records(
    scope_kind,scope_id,subject_domain,subject_kind,subject_id,evidence_kind,
    source_kind,source_key,actor_user_id,value,confidence,observed_at,provenance,metadata
  ) values (
    'ledger',p_target_ledger_id,'finance','financial_source_transaction',v_transaction.id::text,
    'transaction_observation','financial_source_evidence_projection',
    v_transaction.id::text||':'||v_source_evidence_observation.id::text,auth.uid(),
    jsonb_build_object(
      'financialTransactionId',v_transaction.id,
      'financialSourceAccountId',v_transaction.financial_source_account_id,
      'financialEvidenceObservationId',v_source_evidence_observation.id,
      'sourceEvidenceRecordId',v_source_evidence_observation.evidence_record_id,
      'observationSha256',v_source_evidence_observation.observation_sha256,
      'providerTransactionKey',v_transaction.provider_transaction_key,
      'ledgerSubjectEntityId',v_canonical_ledger.subject_entity_id,
      'sourceAccountHolderEntityIds',v_holder_entity_ids
    ),1,v_source_evidence_observation.observed_at,
    jsonb_build_object(
      'authority','promote_financial_source_transaction_expense_self_api_v2',
      'rawObservedSnapshotRemainsInSourceEvidenceRecord',true,
      'sourceEvidenceRecordId',v_source_evidence_observation.evidence_record_id
    ),'{}'::jsonb
  ) on conflict(scope_kind,scope_id,source_kind,source_key) do nothing
  returning id into v_ledger_evidence_record_id;

  if v_ledger_evidence_record_id is null then
    select evidence.id into v_ledger_evidence_record_id
    from atlas.evidence_records evidence
    where evidence.scope_kind='ledger' and evidence.scope_id=p_target_ledger_id
      and evidence.source_kind='financial_source_evidence_projection'
      and evidence.source_key=v_transaction.id::text||':'||v_source_evidence_observation.id::text;
  end if;

  v_link_id:=atlas.link_organization_spend_evidence_core_v1(
    p_target_ledger_id,v_organization_id,v_spend_occurrence_id,null,v_ledger_evidence_record_id,
    'transaction_observation',v_principal_id,v_membership_id,
    jsonb_build_object(
      'financialTransactionId',v_transaction.id,
      'financialSourceAccountId',v_transaction.financial_source_account_id,
      'sourceEvidenceRecordId',v_source_evidence_observation.evidence_record_id,
      'ledgerSubjectEntityId',v_canonical_ledger.subject_entity_id
    )
  );

  insert into atlas.financial_source_transaction_spend_promotions(
    financial_transaction_id,review_event_id,target_ledger_id,spend_occurrence_id,evidence_record_id,
    promoted_by_principal_id,promoted_by_membership_id,metadata
  ) values (
    v_transaction.id,v_review.id,p_target_ledger_id,v_spend_occurrence_id,v_ledger_evidence_record_id,
    v_principal_id,v_membership_id,
    jsonb_build_object(
      'evidenceLinkId',v_link_id,'ledgerSubjectEntityId',v_canonical_ledger.subject_entity_id,
      'compatibilityOrganizationId',v_organization_id,
      'financialSourceAccountId',v_transaction.financial_source_account_id,
      'sourceAccountHolderEntityIds',v_holder_entity_ids,'fundingInference',v_funding_inference
    )
  );

  return jsonb_build_object(
    'contractVersion','promote_financial_source_transaction_expense_self_api_v2',
    'state','promoted','financialTransactionId',v_transaction.id,'reviewEventId',v_review.id,
    'targetLedgerId',p_target_ledger_id,'ledgerSubjectEntityId',v_canonical_ledger.subject_entity_id,
    'compatibilityOrganizationId',v_organization_id,'spendOccurrenceId',v_spend_occurrence_id,
    'evidenceRecordId',v_ledger_evidence_record_id,'sourceEvidenceRecordId',v_source_evidence_observation.evidence_record_id,
    'grossAmount',v_amount,'currency',v_transaction.currency,'fundingKind',v_funding_kind,
    'fundingInference',v_funding_inference,'sourceAccountHolderEntityIds',v_holder_entity_ids
  );
end;
$$;

revoke all on function atlas.promote_financial_source_transaction_expense_self_api_v2(uuid,uuid)
  from public,anon;
grant execute on function atlas.promote_financial_source_transaction_expense_self_api_v2(uuid,uuid)
  to authenticated;

comment on function atlas.replace_financial_source_transaction_review_self_api_v2(uuid,text,jsonb,jsonb) is
  'Confirms a full-amount bookkeeping review against the exact current account-centered financial evidence observation without rewriting source evidence.';
comment on function atlas.promote_financial_source_transaction_expense_self_api_v2(uuid,uuid) is
  'Promotes the current reviewed operating-expense share into Package 5 Spend. Cross-entity account ownership remains unresolved until a separate governed reporting/funding relationship establishes its meaning.';
