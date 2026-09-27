-- Financial source account-holder / Reality bridge v1
--
-- Technical connected-source custody is not financial account ownership.
-- A user may connect or import a source whose legal/economic account holder is a different
-- canonical Reality entity. Account holders are therefore designated separately and may be
-- plural (for example, a joint account).
--
-- Canonical Ledger subject drives bookkeeping allocation. The legacy atlas organization is
-- consulted only when adapting an approved expense into Package 5 organization Spend.

create table if not exists atlas.financial_source_account_holders (
  id uuid primary key default gen_random_uuid(),
  connected_source_id uuid not null references atlas.connected_sources(id) on delete restrict,
  holder_entity_id uuid not null references reality.entities(id) on delete restrict,
  established_by_principal_id uuid references atlas.principals(id) on delete restrict,
  established_by_user_id uuid references auth.users(id) on delete restrict,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  established_at timestamptz not null default now(),
  constraint financial_source_account_holders_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint financial_source_account_holders_metadata_object check (jsonb_typeof(metadata)='object'),
  unique (connected_source_id,holder_entity_id)
);

create index if not exists financial_source_account_holders_entity_idx
  on atlas.financial_source_account_holders(holder_entity_id,connected_source_id);

alter table atlas.financial_source_account_holders enable row level security;
revoke all on table atlas.financial_source_account_holders from public,anon,authenticated;

create or replace function atlas.designate_financial_source_account_holder_self_api_v1(
  p_connected_source_id uuid,
  p_holder_entity_id uuid,
  p_provenance jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth,reality
as $$
declare
  v_principal_id uuid;
  v_holder reality.entities%rowtype;
  v_record atlas.financial_source_account_holders%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required.' using errcode='42501';
  end if;
  if p_connected_source_id is null or p_holder_entity_id is null then
    raise exception 'Connected source and account-holder Reality entity are required.' using errcode='22023';
  end if;
  if p_provenance is null or jsonb_typeof(p_provenance)<>'object'
     or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Account-holder provenance and metadata must be JSON objects.' using errcode='22023';
  end if;
  if not atlas.financial_connected_source_authorized_self_v1(p_connected_source_id) then
    raise exception 'Financial source authority required.' using errcode='42501';
  end if;

  select * into v_holder
  from reality.entities entity
  where entity.id=p_holder_entity_id
    and entity.identity_state='canonical';
  if v_holder.id is null then
    raise exception 'Canonical Reality account-holder entity required.' using errcode='23503';
  end if;

  v_principal_id:=atlas.current_principal_id_v1();
  if v_principal_id is null then
    raise exception 'Principal context required.' using errcode='42501';
  end if;

  insert into atlas.financial_source_account_holders(
    connected_source_id,holder_entity_id,established_by_principal_id,established_by_user_id,
    provenance,metadata
  ) values (
    p_connected_source_id,p_holder_entity_id,v_principal_id,auth.uid(),
    p_provenance || jsonb_build_object(
      'authority','designate_financial_source_account_holder_self_api_v1',
      'sourceCustodyDoesNotEstablishAccountOwnership',true
    ),
    p_metadata
  ) on conflict(connected_source_id,holder_entity_id) do nothing
  returning * into v_record;

  if v_record.id is null then
    select * into v_record
    from atlas.financial_source_account_holders holder
    where holder.connected_source_id=p_connected_source_id
      and holder.holder_entity_id=p_holder_entity_id;
    return jsonb_build_object(
      'contractVersion','designate_financial_source_account_holder_self_v1',
      'state','unchanged',
      'connectedSourceId',p_connected_source_id,
      'holderEntityId',p_holder_entity_id,
      'holderDisplayName',v_holder.display_name
    );
  end if;

  return jsonb_build_object(
    'contractVersion','designate_financial_source_account_holder_self_v1',
    'state','designated',
    'accountHolderId',v_record.id,
    'connectedSourceId',p_connected_source_id,
    'holderEntityId',p_holder_entity_id,
    'holderDisplayName',v_holder.display_name
  );
end;
$$;

revoke all on function atlas.designate_financial_source_account_holder_self_api_v1(uuid,uuid,jsonb,jsonb)
  from public,anon;
grant execute on function atlas.designate_financial_source_account_holder_self_api_v1(uuid,uuid,jsonb,jsonb)
  to authenticated;

create or replace function atlas.financial_source_account_holders_self_api_v1(p_connected_source_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth,reality
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required.' using errcode='42501';
  end if;
  if not atlas.financial_connected_source_authorized_self_v1(p_connected_source_id) then
    raise exception 'Financial source authority required.' using errcode='42501';
  end if;

  return jsonb_build_object(
    'contractVersion','financial_source_account_holders_self_v1',
    'connectedSourceId',p_connected_source_id,
    'holders',coalesce((
      select jsonb_agg(jsonb_build_object(
        'accountHolderId',holder.id,
        'entityId',entity.id,
        'stableKey',entity.stable_key,
        'entityKind',entity.entity_kind,
        'displayName',entity.display_name,
        'identityState',entity.identity_state,
        'establishedAt',holder.established_at
      ) order by entity.display_name,entity.id)
      from atlas.financial_source_account_holders holder
      join reality.entities entity on entity.id=holder.holder_entity_id
      where holder.connected_source_id=p_connected_source_id
    ),'[]'::jsonb),
    'truthBoundary',jsonb_build_object(
      'technicalSourceCustodyDoesNotEstablishAccountOwnership',true,
      'accountOwnershipDoesNotEstablishOperationalBeneficiary',true,
      'multipleAccountHoldersPermitted',true
    )
  );
end;
$$;

revoke all on function atlas.financial_source_account_holders_self_api_v1(uuid) from public,anon;
grant execute on function atlas.financial_source_account_holders_self_api_v1(uuid) to authenticated;

create or replace function atlas.promote_financial_source_transaction_expense_self_api_v1(
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
  v_principal_id uuid;
  v_person_id uuid;
  v_organization_id uuid;
  v_membership_id uuid;
  v_funding_kind text;
  v_payer_membership_id uuid;
  v_amount numeric;
  v_allocations jsonb;
  v_spend jsonb;
  v_spend_occurrence_id uuid;
  v_observation_hash text;
  v_observed_at timestamptz;
  v_evidence_record_id uuid;
  v_link_id uuid;
  v_holder_entity_ids jsonb:='[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required.' using errcode='42501';
  end if;

  select * into v_transaction
  from atlas.financial_source_transactions transaction
  where transaction.id=p_financial_transaction_id
  for update;
  if v_transaction.id is null then
    raise exception 'Financial source transaction not found.' using errcode='23503';
  end if;
  if v_transaction.source_amount>=0 then
    raise exception 'Only source outflows may be promoted as Spend.' using errcode='22023';
  end if;
  if not atlas.financial_connected_source_authorized_self_v1(v_transaction.connected_source_id) then
    raise exception 'Financial source authority required.' using errcode='42501';
  end if;

  select * into v_canonical_ledger
  from ledger.ledgers canonical_ledger
  where canonical_ledger.id=p_target_ledger_id
    and canonical_ledger.ledger_state='active'
    and canonical_ledger.retired_at is null;
  if v_canonical_ledger.id is null then
    raise exception 'Active canonical Ledger required.' using errcode='23503';
  end if;

  perform atlas.current_active_ledger_seat_v1(p_target_ledger_id);

  v_principal_id:=atlas.current_principal_id_v1();
  v_person_id:=atlas.current_person_id_v1();
  if v_principal_id is null or v_person_id is null then
    raise exception 'Reality Person and Principal context required.' using errcode='42501';
  end if;

  -- Package 5 remains organization-shaped. Resolve its routing carrier only at this adapter.
  select participation.organization_id
  into v_organization_id
  from atlas.ledger_organization_participations participation
  join atlas.ledgers legacy_ledger
    on legacy_ledger.id=participation.ledger_id
   and legacy_ledger.status='active'
  join compatibility.legacy_bindings binding
    on binding.legacy_schema='atlas'
   and binding.legacy_table='organizations'
   and binding.legacy_key=participation.organization_id::text
   and binding.disposition='maps_to'
   and binding.new_schema='reality'
   and binding.new_table='entities'
   and binding.new_id=v_canonical_ledger.subject_entity_id
  where participation.ledger_id=p_target_ledger_id
    and participation.status='active'
  order by participation.created_at,participation.organization_id
  limit 1;

  if v_organization_id is null then
    return jsonb_build_object(
      'contractVersion','promote_financial_source_transaction_expense_self_api_v1',
      'state','compatibility_required',
      'financialTransactionId',p_financial_transaction_id,
      'targetLedgerId',p_target_ledger_id,
      'ledgerSubjectEntityId',v_canonical_ledger.subject_entity_id,
      'reason','Package 5 organization routing carrier is unavailable for this canonical Ledger.'
    );
  end if;

  v_membership_id:=atlas.current_organization_membership_v1(v_organization_id);
  if v_membership_id is null then
    return jsonb_build_object(
      'contractVersion','promote_financial_source_transaction_expense_self_api_v1',
      'state','compatibility_required',
      'financialTransactionId',p_financial_transaction_id,
      'targetLedgerId',p_target_ledger_id,
      'ledgerSubjectEntityId',v_canonical_ledger.subject_entity_id,
      'compatibilityOrganizationId',v_organization_id,
      'reason','Package 5 actor membership is unavailable for this canonical Ledger.'
    );
  end if;

  select * into v_review
  from atlas.financial_source_transaction_review_events review
  where review.financial_transaction_id=p_financial_transaction_id
  order by review.review_revision desc
  limit 1;
  if v_review.id is null then
    raise exception 'A confirmed financial transaction review is required before Spend promotion.' using errcode='55000';
  end if;
  if v_review.source_observation_id<>v_transaction.current_observation_id then
    return jsonb_build_object(
      'contractVersion','promote_financial_source_transaction_expense_self_api_v1',
      'state','requires_review',
      'financialTransactionId',p_financial_transaction_id,
      'reviewEventId',v_review.id,
      'reviewedObservationId',v_review.source_observation_id,
      'currentObservationId',v_transaction.current_observation_id
    );
  end if;

  select * into v_existing
  from atlas.financial_source_transaction_spend_promotions promotion
  where promotion.financial_transaction_id=p_financial_transaction_id
    and promotion.target_ledger_id=p_target_ledger_id;
  if v_existing.id is not null then
    if v_existing.review_event_id=v_review.id then
      return jsonb_build_object(
        'contractVersion','promote_financial_source_transaction_expense_self_api_v1',
        'state','unchanged',
        'financialTransactionId',p_financial_transaction_id,
        'reviewEventId',v_review.id,
        'spendOccurrenceId',v_existing.spend_occurrence_id
      );
    end if;
    return jsonb_build_object(
      'contractVersion','promote_financial_source_transaction_expense_self_api_v1',
      'state','requires_correction',
      'financialTransactionId',p_financial_transaction_id,
      'previousReviewEventId',v_existing.review_event_id,
      'currentReviewEventId',v_review.id,
      'spendOccurrenceId',v_existing.spend_occurrence_id
    );
  end if;

  select sum(allocation.allocated_amount),
         jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'amount',allocation.allocated_amount,
           'operationalPurpose',allocation.operational_purpose,
           'subjectDomain',allocation.subject_domain,
           'subjectKind',allocation.subject_kind,
           'subjectId',allocation.subject_id
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
  from atlas.financial_source_account_holders holder
  where holder.connected_source_id=v_transaction.connected_source_id;

  -- Infer funding from designated financial account ownership, never connector custody.
  if exists(
    select 1 from atlas.financial_source_account_holders holder
    where holder.connected_source_id=v_transaction.connected_source_id
      and holder.holder_entity_id=v_canonical_ledger.subject_entity_id
  ) then
    v_funding_kind:='organization';
    v_payer_membership_id:=null;
  elsif exists(
    select 1 from atlas.financial_source_account_holders holder
    where holder.connected_source_id=v_transaction.connected_source_id
      and holder.holder_entity_id=v_person_id
  ) then
    v_funding_kind:='organization_member';
    v_payer_membership_id:=v_membership_id;
  elsif jsonb_array_length(v_holder_entity_ids)>0 then
    v_funding_kind:='external_party';
    v_payer_membership_id:=null;
  else
    v_funding_kind:='unresolved';
    v_payer_membership_id:=null;
  end if;

  v_spend:=atlas.record_organization_spend_core_v1(
    p_target_ledger_id,
    v_organization_id,
    v_principal_id,
    v_membership_id,
    null,
    v_transaction.occurred_on,
    v_transaction.occurred_at,
    v_amount,
    v_transaction.currency,
    v_funding_kind,
    v_payer_membership_id,
    null,
    coalesce(v_transaction.source_party_label,v_transaction.raw_description),
    'connected_source',
    'financial_source_transaction',
    v_transaction.id::text,
    v_allocations,
    jsonb_build_object(
      'authority','promote_financial_source_transaction_expense_self_api_v1',
      'financialTransactionId',v_transaction.id,
      'connectedSourceId',v_transaction.connected_source_id,
      'sourceObservationId',v_transaction.current_observation_id,
      'reviewEventId',v_review.id,
      'ledgerSubjectEntityId',v_canonical_ledger.subject_entity_id,
      'sourceAccountHolderEntityIds',v_holder_entity_ids,
      'sourceCustodyIndependentOfAccountOwnership',true,
      'accountOwnershipIndependentOfOperationalTarget',true,
      'compatibilityOrganizationIsRoutingOnly',true
    ),
    jsonb_build_object(
      'importedFromFinancialSource',true,
      'providerTransactionKey',v_transaction.provider_transaction_key,
      'ledgerSubjectEntityId',v_canonical_ledger.subject_entity_id
    )
  );
  v_spend_occurrence_id:=(v_spend->>'spendOccurrenceId')::uuid;

  select observation.payload_sha256,observation.observed_at
  into v_observation_hash,v_observed_at
  from atlas.connected_source_observations observation
  where observation.id=v_transaction.current_observation_id;

  insert into atlas.evidence_records(
    scope_kind,scope_id,subject_domain,subject_kind,subject_id,evidence_kind,
    source_kind,source_key,actor_user_id,value,confidence,observed_at,provenance,metadata
  ) values (
    'ledger',p_target_ledger_id,'finance','financial_source_transaction',v_transaction.id::text,
    'transaction_observation','connected_source_observation',v_transaction.id::text,auth.uid(),
    jsonb_build_object(
      'financialTransactionId',v_transaction.id,
      'connectedSourceId',v_transaction.connected_source_id,
      'sourceObservationId',v_transaction.current_observation_id,
      'payloadSha256',v_observation_hash,
      'providerTransactionKey',v_transaction.provider_transaction_key,
      'ledgerSubjectEntityId',v_canonical_ledger.subject_entity_id,
      'sourceAccountHolderEntityIds',v_holder_entity_ids
    ),
    1,v_observed_at,
    jsonb_build_object(
      'authority','promote_financial_source_transaction_expense_self_api_v1',
      'rawEvidenceRemainsInConnectedSourceObservation',true
    ),
    '{}'::jsonb
  ) on conflict(scope_kind,scope_id,source_kind,source_key) do nothing
  returning id into v_evidence_record_id;

  if v_evidence_record_id is null then
    select evidence.id into v_evidence_record_id
    from atlas.evidence_records evidence
    where evidence.scope_kind='ledger'
      and evidence.scope_id=p_target_ledger_id
      and evidence.source_kind='connected_source_observation'
      and evidence.source_key=v_transaction.id::text;
  end if;

  v_link_id:=atlas.link_organization_spend_evidence_core_v1(
    p_target_ledger_id,v_organization_id,v_spend_occurrence_id,null,v_evidence_record_id,
    'transaction_observation',v_principal_id,v_membership_id,
    jsonb_build_object(
      'financialTransactionId',v_transaction.id,
      'ledgerSubjectEntityId',v_canonical_ledger.subject_entity_id
    )
  );

  insert into atlas.financial_source_transaction_spend_promotions(
    financial_transaction_id,review_event_id,target_ledger_id,spend_occurrence_id,evidence_record_id,
    promoted_by_principal_id,promoted_by_membership_id,metadata
  ) values (
    v_transaction.id,v_review.id,p_target_ledger_id,v_spend_occurrence_id,v_evidence_record_id,
    v_principal_id,v_membership_id,
    jsonb_build_object(
      'evidenceLinkId',v_link_id,
      'ledgerSubjectEntityId',v_canonical_ledger.subject_entity_id,
      'compatibilityOrganizationId',v_organization_id,
      'sourceAccountHolderEntityIds',v_holder_entity_ids
    )
  );

  return jsonb_build_object(
    'contractVersion','promote_financial_source_transaction_expense_self_api_v1',
    'state','promoted',
    'financialTransactionId',v_transaction.id,
    'reviewEventId',v_review.id,
    'targetLedgerId',p_target_ledger_id,
    'ledgerSubjectEntityId',v_canonical_ledger.subject_entity_id,
    'compatibilityOrganizationId',v_organization_id,
    'spendOccurrenceId',v_spend_occurrence_id,
    'evidenceRecordId',v_evidence_record_id,
    'grossAmount',v_amount,
    'currency',v_transaction.currency,
    'fundingKind',v_funding_kind,
    'sourceAccountHolderEntityIds',v_holder_entity_ids
  );
end;
$$;

revoke all on function atlas.promote_financial_source_transaction_expense_self_api_v1(uuid,uuid)
  from public,anon;
grant execute on function atlas.promote_financial_source_transaction_expense_self_api_v1(uuid,uuid)
  to authenticated;

comment on table atlas.financial_source_account_holders is
  'Canonical Reality entities designated as holders of a financial account represented by a connected source. This is financial ownership evidence, not connector custody and not operational beneficiary.';
comment on function atlas.designate_financial_source_account_holder_self_api_v1(uuid,uuid,jsonb,jsonb) is
  'Designates a canonical Reality entity as an account holder for an authorized financial source without changing source custody or transaction allocation.';
comment on function atlas.promote_financial_source_transaction_expense_self_api_v1(uuid,uuid) is
  'Promotes the current reviewed operating-expense share into Package 5 Spend using canonical Ledger subject for meaning, Reality account holders for funding inference, and legacy organization participation only as a routing adapter.';
