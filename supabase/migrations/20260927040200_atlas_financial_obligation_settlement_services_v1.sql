-- Atlas governed financial obligation + settlement services v1.
-- Product code writes economic truth only through these membranes. Journal posting remains downstream.

alter table atlas.financial_obligation_state_events
  drop constraint if exists financial_obligation_state_events_kind_check;
alter table atlas.financial_obligation_state_events
  add constraint financial_obligation_state_events_kind_check check (
    event_kind in (
      'condition_satisfied','condition_failed','became_unconditional','earned','released',
      'became_nonrefundable','forgiven','written_off','voided','other'
    )
  );

create or replace function atlas.establish_financial_obligation_self_api_v1(
  p_accounting_book_id uuid,
  p_obligation_key text,
  p_obligation_kind text,
  p_face_amount numeric,
  p_currency text,
  p_incurred_on date,
  p_obligor_entity_id uuid,
  p_obligee_entity_id uuid,
  p_due_on date default null,
  p_condition_state text default 'not_applicable',
  p_entitlement_state text default 'not_applicable',
  p_refundability_state text default 'not_applicable',
  p_evidence_record_id uuid default null,
  p_provenance jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_key text:=btrim(coalesce(p_obligation_key,''));
  v_kind text:=lower(btrim(coalesce(p_obligation_kind,'')));
  v_currency text:=upper(btrim(coalesce(p_currency,'')));
  v_condition text:=lower(btrim(coalesce(p_condition_state,'')));
  v_entitlement text:=lower(btrim(coalesce(p_entitlement_state,'')));
  v_refundability text:=lower(btrim(coalesce(p_refundability_state,'')));
  v_row atlas.financial_obligations%rowtype;
  v_principal uuid;
  v_inserted boolean:=false;
begin
  if not atlas.accounting_book_authorized_self_v1(p_accounting_book_id) then
    raise exception 'Accounting book authority required.' using errcode='42501';
  end if;
  if v_key='' or p_face_amount is null or p_face_amount<=0 or p_incurred_on is null
     or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Obligation key, positive amount, currency, and incurred date are required.' using errcode='22023';
  end if;
  if p_obligor_entity_id is null or p_obligee_entity_id is null or p_obligor_entity_id=p_obligee_entity_id then
    raise exception 'Distinct canonical obligor and obligee entities are required.' using errcode='22023';
  end if;
  if p_due_on is not null and p_due_on<p_incurred_on then
    raise exception 'Obligation due date cannot precede incurred date.' using errcode='22023';
  end if;
  if v_condition not in ('not_applicable','conditional','satisfied','released','failed')
     or v_entitlement not in ('not_applicable','unearned','earned')
     or v_refundability not in ('not_applicable','refundable','conditional','nonrefundable') then
    raise exception 'Unsupported obligation condition, entitlement, or refundability state.' using errcode='22023';
  end if;
  if p_provenance is null or jsonb_typeof(p_provenance)<>'object'
     or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Obligation provenance and metadata must be JSON objects.' using errcode='22023';
  end if;
  if not exists(select 1 from reality.entities where id=p_obligor_entity_id and identity_state='canonical')
     or not exists(select 1 from reality.entities where id=p_obligee_entity_id and identity_state='canonical') then
    raise exception 'Obligor and obligee must be canonical Reality entities.' using errcode='23503';
  end if;

  v_principal:=atlas.current_principal_id_v1();
  insert into atlas.financial_obligations(
    accounting_book_id,obligation_key,obligation_kind,face_amount,currency,incurred_on,due_on,
    condition_state,entitlement_state,refundability_state,evidence_record_id,provenance,metadata,
    created_by_principal_id,created_by_user_id
  ) values (
    p_accounting_book_id,v_key,v_kind,p_face_amount,v_currency,p_incurred_on,p_due_on,
    v_condition,v_entitlement,v_refundability,p_evidence_record_id,
    p_provenance||jsonb_build_object(
      'authority','establish_financial_obligation_self_api_v1',
      'journalPosted',false,
      'sourceMovementCreated',false
    ),p_metadata,v_principal,auth.uid()
  ) on conflict(accounting_book_id,obligation_key) do nothing
  returning * into v_row;

  if v_row.id is not null then
    v_inserted:=true;
    insert into atlas.financial_obligation_parties(obligation_id,entity_id,role_kind,provenance)
    values
      (v_row.id,p_obligor_entity_id,'obligor',jsonb_build_object('authority','establish_financial_obligation_self_api_v1')),
      (v_row.id,p_obligee_entity_id,'obligee',jsonb_build_object('authority','establish_financial_obligation_self_api_v1'));
  else
    select * into v_row from atlas.financial_obligations
    where accounting_book_id=p_accounting_book_id and obligation_key=v_key;
    if v_row.obligation_kind<>v_kind or v_row.face_amount<>p_face_amount or v_row.currency<>v_currency
       or v_row.incurred_on<>p_incurred_on or v_row.due_on is distinct from p_due_on
       or v_row.condition_state<>v_condition or v_row.entitlement_state<>v_entitlement
       or v_row.refundability_state<>v_refundability or v_row.evidence_record_id is distinct from p_evidence_record_id then
      raise exception 'Obligation key already exists with different immutable economic facts.' using errcode='23505';
    end if;
    if not exists(select 1 from atlas.financial_obligation_parties where obligation_id=v_row.id and entity_id=p_obligor_entity_id and role_kind='obligor')
       or not exists(select 1 from atlas.financial_obligation_parties where obligation_id=v_row.id and entity_id=p_obligee_entity_id and role_kind='obligee') then
      raise exception 'Obligation key already exists with different canonical parties.' using errcode='23505';
    end if;
  end if;

  return jsonb_build_object(
    'contractVersion','financial_obligation_v1',
    'obligationId',v_row.id,
    'created',v_inserted,
    'accountingBookId',v_row.accounting_book_id,
    'obligationKey',v_row.obligation_key,
    'obligationKind',v_row.obligation_kind,
    'faceAmount',v_row.face_amount,
    'currency',v_row.currency,
    'obligorEntityId',p_obligor_entity_id,
    'obligeeEntityId',p_obligee_entity_id,
    'conditionState',v_row.condition_state,
    'entitlementState',v_row.entitlement_state,
    'refundabilityState',v_row.refundability_state,
    'settlementState',v_row.settlement_state,
    'truthBoundary',jsonb_build_object(
      'canonicalPartiesRequired',true,
      'paymentCreated',false,
      'accountingRecognitionEstablished',false,
      'journalPosted',false
    )
  );
end;
$$;
revoke all on function atlas.establish_financial_obligation_self_api_v1(uuid,text,text,numeric,text,date,uuid,uuid,date,text,text,text,uuid,jsonb,jsonb) from public,anon;
grant execute on function atlas.establish_financial_obligation_self_api_v1(uuid,text,text,numeric,text,date,uuid,uuid,date,text,text,text,uuid,jsonb,jsonb) to authenticated;

create or replace function atlas.record_financial_settlement_self_api_v1(
  p_accounting_book_id uuid,
  p_settlement_key text,
  p_settlement_on date,
  p_settlement_kind text,
  p_amount numeric,
  p_currency text,
  p_medium_kind text,
  p_from_entity_id uuid,
  p_from_role text,
  p_to_entity_id uuid,
  p_to_role text,
  p_source_domain text default null,
  p_source_kind text default null,
  p_source_id text default null,
  p_evidence_record_id uuid default null,
  p_provenance jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_key text:=btrim(coalesce(p_settlement_key,''));
  v_kind text:=lower(btrim(coalesce(p_settlement_kind,'')));
  v_currency text:=upper(btrim(coalesce(p_currency,'')));
  v_medium text:=lower(btrim(coalesce(p_medium_kind,'')));
  v_from_role text:=lower(btrim(coalesce(p_from_role,'')));
  v_to_role text:=lower(btrim(coalesce(p_to_role,'')));
  v_row atlas.financial_settlements%rowtype;
  v_principal uuid;
  v_inserted boolean:=false;
  v_source_count integer;
begin
  if not atlas.accounting_book_authorized_self_v1(p_accounting_book_id) then
    raise exception 'Accounting book authority required.' using errcode='42501';
  end if;
  if v_key='' or p_settlement_on is null or p_amount is null or p_amount<=0 or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Settlement key, date, positive amount, and currency are required.' using errcode='22023';
  end if;
  if p_from_entity_id is null or p_to_entity_id is null or p_from_entity_id=p_to_entity_id then
    raise exception 'Distinct canonical settlement parties are required; internal account transfers remain source transfers, not economic settlements.' using errcode='22023';
  end if;
  if not exists(select 1 from reality.entities where id=p_from_entity_id and identity_state='canonical')
     or not exists(select 1 from reality.entities where id=p_to_entity_id and identity_state='canonical') then
    raise exception 'Settlement parties must be canonical Reality entities.' using errcode='23503';
  end if;
  if p_provenance is null or jsonb_typeof(p_provenance)<>'object'
     or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Settlement provenance and metadata must be JSON objects.' using errcode='22023';
  end if;
  v_source_count := (case when nullif(btrim(coalesce(p_source_domain,'')),'') is null then 0 else 1 end)
                  + (case when nullif(btrim(coalesce(p_source_kind,'')),'') is null then 0 else 1 end)
                  + (case when nullif(btrim(coalesce(p_source_id,'')),'') is null then 0 else 1 end);
  if v_source_count not in (0,3) then
    raise exception 'Source domain, kind, and id must be supplied together.' using errcode='22023';
  end if;

  v_principal:=atlas.current_principal_id_v1();
  insert into atlas.financial_settlements(
    accounting_book_id,settlement_key,settlement_on,settlement_kind,amount,currency,medium_kind,
    settlement_state,evidence_record_id,provenance,metadata,created_by_principal_id,created_by_user_id
  ) values (
    p_accounting_book_id,v_key,p_settlement_on,v_kind,p_amount,v_currency,v_medium,'confirmed',p_evidence_record_id,
    p_provenance||jsonb_build_object(
      'authority','record_financial_settlement_self_api_v1',
      'sourceMovementCopied',false,
      'journalPosted',false
    ),p_metadata,v_principal,auth.uid()
  ) on conflict(accounting_book_id,settlement_key) do nothing
  returning * into v_row;

  if v_row.id is not null then
    v_inserted:=true;
    insert into atlas.financial_settlement_roles(settlement_id,entity_id,role_kind,provenance)
    values
      (v_row.id,p_from_entity_id,v_from_role,jsonb_build_object('authority','record_financial_settlement_self_api_v1')),
      (v_row.id,p_to_entity_id,v_to_role,jsonb_build_object('authority','record_financial_settlement_self_api_v1'));
    if v_source_count=3 then
      insert into atlas.financial_settlement_source_links(
        settlement_id,source_domain,source_kind,source_id,relation_kind,evidence_record_id,provenance
      ) values (
        v_row.id,btrim(p_source_domain),btrim(p_source_kind),btrim(p_source_id),'evidence_of',p_evidence_record_id,
        jsonb_build_object('authority','record_financial_settlement_self_api_v1')
      );
    end if;
  else
    select * into v_row from atlas.financial_settlements
    where accounting_book_id=p_accounting_book_id and settlement_key=v_key;
    if v_row.settlement_on<>p_settlement_on or v_row.settlement_kind<>v_kind or v_row.amount<>p_amount
       or v_row.currency<>v_currency or v_row.medium_kind<>v_medium
       or v_row.evidence_record_id is distinct from p_evidence_record_id then
      raise exception 'Settlement key already exists with different immutable economic facts.' using errcode='23505';
    end if;
    if not exists(select 1 from atlas.financial_settlement_roles where settlement_id=v_row.id and entity_id=p_from_entity_id and role_kind=v_from_role)
       or not exists(select 1 from atlas.financial_settlement_roles where settlement_id=v_row.id and entity_id=p_to_entity_id and role_kind=v_to_role) then
      raise exception 'Settlement key already exists with different canonical party roles.' using errcode='23505';
    end if;
  end if;

  return jsonb_build_object(
    'contractVersion','financial_settlement_v1',
    'settlementId',v_row.id,
    'created',v_inserted,
    'accountingBookId',v_row.accounting_book_id,
    'settlementKey',v_row.settlement_key,
    'settlementOn',v_row.settlement_on,
    'settlementKind',v_row.settlement_kind,
    'amount',v_row.amount,
    'currency',v_row.currency,
    'settlementState',v_row.settlement_state,
    'truthBoundary',jsonb_build_object(
      'sourceTransactionCopied',false,
      'obligationSatisfiedUntilAllocated',false,
      'accountingRecognitionEstablished',false,
      'journalPosted',false
    )
  );
end;
$$;
revoke all on function atlas.record_financial_settlement_self_api_v1(uuid,text,date,text,numeric,text,text,uuid,text,uuid,text,text,text,text,uuid,jsonb,jsonb) from public,anon;
grant execute on function atlas.record_financial_settlement_self_api_v1(uuid,text,date,text,numeric,text,text,uuid,text,uuid,text,text,text,text,uuid,jsonb,jsonb) to authenticated;

create or replace function atlas.allocate_financial_settlement_self_api_v1(
  p_settlement_id uuid,
  p_obligation_id uuid,
  p_allocation_kind text,
  p_applied_amount numeric,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_book uuid;
  v_obligation_book uuid;
  v_currency text;
  v_row atlas.financial_settlement_allocations%rowtype;
  v_state text;
  v_remaining numeric;
begin
  select accounting_book_id,currency into v_book,v_currency from atlas.financial_settlements where id=p_settlement_id;
  select accounting_book_id into v_obligation_book from atlas.financial_obligations where id=p_obligation_id;
  if v_book is null or v_obligation_book is null or v_book<>v_obligation_book then
    raise exception 'Settlement and obligation in one accounting book are required.' using errcode='23503';
  end if;
  if not atlas.accounting_book_authorized_self_v1(v_book) then raise exception 'Accounting book authority required.' using errcode='42501'; end if;
  if p_applied_amount is null or p_applied_amount<=0 then raise exception 'Positive applied amount required.' using errcode='22023'; end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then raise exception 'Allocation metadata must be a JSON object.' using errcode='22023'; end if;

  perform 1 from atlas.financial_settlements where id=p_settlement_id for update;
  perform 1 from atlas.financial_obligations where id=p_obligation_id for update;

  insert into atlas.financial_settlement_allocations(
    settlement_id,obligation_id,allocation_kind,applied_amount,currency,provenance,metadata
  ) values (
    p_settlement_id,p_obligation_id,lower(btrim(coalesce(p_allocation_kind,''))),p_applied_amount,v_currency,
    jsonb_build_object('authority','allocate_financial_settlement_self_api_v1'),p_metadata
  ) returning * into v_row;

  v_state:=atlas.refresh_financial_obligation_settlement_state_core_v1(p_obligation_id);
  select face_amount-coalesce((
    select sum(a.applied_amount)
    from atlas.financial_settlement_allocations a
    join atlas.financial_settlements s on s.id=a.settlement_id and s.settlement_state='confirmed'
    where a.obligation_id=p_obligation_id
  ),0) into v_remaining from atlas.financial_obligations where id=p_obligation_id;

  return jsonb_build_object(
    'contractVersion','financial_settlement_allocation_v1',
    'allocationId',v_row.id,
    'settlementId',p_settlement_id,
    'obligationId',p_obligation_id,
    'appliedAmount',v_row.applied_amount,
    'currency',v_row.currency,
    'obligationSettlementState',v_state,
    'obligationRemainingAmount',v_remaining,
    'journalPosted',false
  );
end;
$$;
revoke all on function atlas.allocate_financial_settlement_self_api_v1(uuid,uuid,text,numeric,jsonb) from public,anon;
grant execute on function atlas.allocate_financial_settlement_self_api_v1(uuid,uuid,text,numeric,jsonb) to authenticated;

create or replace function atlas.void_financial_settlement_self_api_v1(
  p_settlement_id uuid,
  p_reason text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_book uuid;
  v_state text;
  v_obligation_id uuid;
begin
  select accounting_book_id,settlement_state into v_book,v_state
  from atlas.financial_settlements where id=p_settlement_id for update;
  if v_book is null then raise exception 'Financial settlement not found.' using errcode='P0002'; end if;
  if not atlas.accounting_book_authorized_self_v1(v_book) then raise exception 'Accounting book authority required.' using errcode='42501'; end if;
  if btrim(coalesce(p_reason,''))='' then raise exception 'Void reason required.' using errcode='22023'; end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then raise exception 'Void metadata must be a JSON object.' using errcode='22023'; end if;
  if v_state='voided' then return jsonb_build_object('contractVersion','financial_settlement_void_v1','settlementId',p_settlement_id,'settlementState','voided','alreadyVoided',true); end if;

  update atlas.financial_settlements
  set settlement_state='voided',
      provenance=provenance||jsonb_build_object('voidReason',p_reason,'voidedBy','void_financial_settlement_self_api_v1'),
      metadata=metadata||p_metadata,
      updated_at=now()
  where id=p_settlement_id;

  for v_obligation_id in
    select distinct obligation_id from atlas.financial_settlement_allocations where settlement_id=p_settlement_id
  loop
    perform atlas.refresh_financial_obligation_settlement_state_core_v1(v_obligation_id);
  end loop;

  return jsonb_build_object('contractVersion','financial_settlement_void_v1','settlementId',p_settlement_id,'settlementState','voided','alreadyVoided',false,'journalReversalCreated',false);
end;
$$;
revoke all on function atlas.void_financial_settlement_self_api_v1(uuid,text,jsonb) from public,anon;
grant execute on function atlas.void_financial_settlement_self_api_v1(uuid,text,jsonb) to authenticated;

create or replace function atlas.record_financial_obligation_state_event_self_api_v1(
  p_obligation_id uuid,
  p_event_key text,
  p_event_on date,
  p_event_kind text,
  p_event_amount numeric default null,
  p_evidence_record_id uuid default null,
  p_provenance jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_book uuid;
  v_kind text:=lower(btrim(coalesce(p_event_kind,'')));
  v_row atlas.financial_obligation_state_events%rowtype;
  v_principal uuid;
begin
  select accounting_book_id into v_book from atlas.financial_obligations where id=p_obligation_id for update;
  if v_book is null then raise exception 'Financial obligation not found.' using errcode='P0002'; end if;
  if not atlas.accounting_book_authorized_self_v1(v_book) then raise exception 'Accounting book authority required.' using errcode='42501'; end if;
  if btrim(coalesce(p_event_key,''))='' or p_event_on is null then raise exception 'State event key and date required.' using errcode='22023'; end if;
  if p_event_amount is not null and p_event_amount<=0 then raise exception 'State event amount must be positive when supplied.' using errcode='22023'; end if;
  if p_provenance is null or jsonb_typeof(p_provenance)<>'object' or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'State event provenance and metadata must be JSON objects.' using errcode='22023';
  end if;
  v_principal:=atlas.current_principal_id_v1();

  insert into atlas.financial_obligation_state_events(
    obligation_id,event_key,event_on,event_kind,event_amount,evidence_record_id,provenance,metadata,created_by_principal_id,created_by_user_id
  ) values (
    p_obligation_id,btrim(p_event_key),p_event_on,v_kind,p_event_amount,p_evidence_record_id,
    p_provenance||jsonb_build_object('authority','record_financial_obligation_state_event_self_api_v1'),p_metadata,v_principal,auth.uid()
  ) returning * into v_row;

  if v_kind in ('condition_satisfied','became_unconditional') then
    update atlas.financial_obligations set condition_state='satisfied',updated_at=now() where id=p_obligation_id;
  elsif v_kind='condition_failed' then
    update atlas.financial_obligations set condition_state='failed',updated_at=now() where id=p_obligation_id;
  elsif v_kind='released' then
    update atlas.financial_obligations set condition_state='released',updated_at=now() where id=p_obligation_id;
  elsif v_kind='earned' then
    update atlas.financial_obligations set entitlement_state='earned',updated_at=now() where id=p_obligation_id;
  elsif v_kind='became_nonrefundable' then
    update atlas.financial_obligations set refundability_state='nonrefundable',updated_at=now() where id=p_obligation_id;
  elsif v_kind='forgiven' then
    update atlas.financial_obligations set settlement_state='forgiven',updated_at=now() where id=p_obligation_id;
  elsif v_kind='written_off' then
    update atlas.financial_obligations set settlement_state='written_off',updated_at=now() where id=p_obligation_id;
  elsif v_kind='voided' then
    update atlas.financial_obligations set settlement_state='voided',updated_at=now() where id=p_obligation_id;
  end if;

  return jsonb_build_object(
    'contractVersion','financial_obligation_state_event_v1',
    'stateEventId',v_row.id,
    'obligationId',p_obligation_id,
    'eventKind',v_row.event_kind,
    'eventOn',v_row.event_on,
    'accountingRecognitionEstablished',false,
    'journalPosted',false
  );
end;
$$;
revoke all on function atlas.record_financial_obligation_state_event_self_api_v1(uuid,text,date,text,numeric,uuid,jsonb,jsonb) from public,anon;
grant execute on function atlas.record_financial_obligation_state_event_self_api_v1(uuid,text,date,text,numeric,uuid,jsonb,jsonb) to authenticated;

create or replace function atlas.link_financial_settlement_lineage_self_api_v1(
  p_child_settlement_id uuid,
  p_parent_settlement_id uuid,
  p_relation_kind text,
  p_provenance jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_book uuid;
  v_row atlas.financial_settlement_lineage%rowtype;
begin
  select accounting_book_id into v_book from atlas.financial_settlements where id=p_child_settlement_id;
  if v_book is null then raise exception 'Child settlement not found.' using errcode='P0002'; end if;
  if not atlas.accounting_book_authorized_self_v1(v_book) then raise exception 'Accounting book authority required.' using errcode='42501'; end if;
  if p_provenance is null or jsonb_typeof(p_provenance)<>'object' or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Lineage provenance and metadata must be JSON objects.' using errcode='22023';
  end if;
  insert into atlas.financial_settlement_lineage(child_settlement_id,parent_settlement_id,relation_kind,provenance,metadata)
  values(p_child_settlement_id,p_parent_settlement_id,lower(btrim(coalesce(p_relation_kind,''))),p_provenance||jsonb_build_object('authority','link_financial_settlement_lineage_self_api_v1'),p_metadata)
  returning * into v_row;
  return jsonb_build_object('contractVersion','financial_settlement_lineage_v1','lineageId',v_row.id,'childSettlementId',v_row.child_settlement_id,'parentSettlementId',v_row.parent_settlement_id,'relationKind',v_row.relation_kind);
end;
$$;
revoke all on function atlas.link_financial_settlement_lineage_self_api_v1(uuid,uuid,text,jsonb,jsonb) from public,anon;
grant execute on function atlas.link_financial_settlement_lineage_self_api_v1(uuid,uuid,text,jsonb,jsonb) to authenticated;

create or replace function atlas.create_financial_settlement_bundle_self_api_v1(
  p_accounting_book_id uuid,
  p_bundle_key text,
  p_bundle_kind text,
  p_settlement_on date,
  p_currency text,
  p_expected_net_amount numeric,
  p_evidence_record_id uuid default null,
  p_provenance jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_row atlas.financial_settlement_bundles%rowtype;
begin
  if not atlas.accounting_book_authorized_self_v1(p_accounting_book_id) then raise exception 'Accounting book authority required.' using errcode='42501'; end if;
  if btrim(coalesce(p_bundle_key,''))='' or p_settlement_on is null or upper(btrim(coalesce(p_currency,''))) !~ '^[A-Z]{3}$' then
    raise exception 'Bundle key, date, and currency required.' using errcode='22023';
  end if;
  if p_provenance is null or jsonb_typeof(p_provenance)<>'object' or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then raise exception 'Bundle provenance and metadata must be JSON objects.' using errcode='22023'; end if;
  insert into atlas.financial_settlement_bundles(
    accounting_book_id,bundle_key,bundle_kind,settlement_on,currency,expected_net_amount,bundle_state,evidence_record_id,provenance,metadata
  ) values (
    p_accounting_book_id,btrim(p_bundle_key),lower(btrim(coalesce(p_bundle_kind,''))),p_settlement_on,upper(btrim(p_currency)),p_expected_net_amount,'open',p_evidence_record_id,
    p_provenance||jsonb_build_object('authority','create_financial_settlement_bundle_self_api_v1'),p_metadata
  ) returning * into v_row;
  return jsonb_build_object('contractVersion','financial_settlement_bundle_v1','bundleId',v_row.id,'bundleKey',v_row.bundle_key,'bundleState',v_row.bundle_state,'expectedNetAmount',v_row.expected_net_amount,'currency',v_row.currency);
end;
$$;
revoke all on function atlas.create_financial_settlement_bundle_self_api_v1(uuid,text,text,date,text,numeric,uuid,jsonb,jsonb) from public,anon;
grant execute on function atlas.create_financial_settlement_bundle_self_api_v1(uuid,text,text,date,text,numeric,uuid,jsonb,jsonb) to authenticated;

create or replace function atlas.add_financial_settlement_bundle_item_self_api_v1(
  p_bundle_id uuid,
  p_settlement_id uuid,
  p_item_kind text,
  p_signed_net_effect numeric,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_book uuid;
  v_row atlas.financial_settlement_bundle_items%rowtype;
begin
  select accounting_book_id into v_book from atlas.financial_settlement_bundles where id=p_bundle_id;
  if v_book is null then raise exception 'Settlement bundle not found.' using errcode='P0002'; end if;
  if not atlas.accounting_book_authorized_self_v1(v_book) then raise exception 'Accounting book authority required.' using errcode='42501'; end if;
  if p_signed_net_effect is null or p_signed_net_effect=0 then raise exception 'Non-zero signed bundle effect required.' using errcode='22023'; end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then raise exception 'Bundle item metadata must be a JSON object.' using errcode='22023'; end if;
  insert into atlas.financial_settlement_bundle_items(bundle_id,settlement_id,item_kind,signed_net_effect,provenance,metadata)
  values(p_bundle_id,p_settlement_id,lower(btrim(coalesce(p_item_kind,''))),p_signed_net_effect,jsonb_build_object('authority','add_financial_settlement_bundle_item_self_api_v1'),p_metadata)
  returning * into v_row;
  return jsonb_build_object('contractVersion','financial_settlement_bundle_item_v1','bundleItemId',v_row.id,'bundleId',v_row.bundle_id,'settlementId',v_row.settlement_id,'signedNetEffect',v_row.signed_net_effect);
end;
$$;
revoke all on function atlas.add_financial_settlement_bundle_item_self_api_v1(uuid,uuid,text,numeric,jsonb) from public,anon;
grant execute on function atlas.add_financial_settlement_bundle_item_self_api_v1(uuid,uuid,text,numeric,jsonb) to authenticated;

create or replace function atlas.reconcile_financial_settlement_bundle_self_api_v1(p_bundle_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_book uuid;
  v_expected numeric;
  v_state text;
  v_sum numeric;
begin
  select accounting_book_id,expected_net_amount,bundle_state into v_book,v_expected,v_state
  from atlas.financial_settlement_bundles where id=p_bundle_id for update;
  if v_book is null then raise exception 'Settlement bundle not found.' using errcode='P0002'; end if;
  if not atlas.accounting_book_authorized_self_v1(v_book) then raise exception 'Accounting book authority required.' using errcode='42501'; end if;
  if v_state='voided' then raise exception 'Voided settlement bundle cannot reconcile.' using errcode='55000'; end if;
  if v_expected is null then raise exception 'Expected net amount is required before reconciliation.' using errcode='22023'; end if;
  select coalesce(sum(i.signed_net_effect),0) into v_sum
  from atlas.financial_settlement_bundle_items i
  join atlas.financial_settlements s on s.id=i.settlement_id and s.settlement_state='confirmed'
  where i.bundle_id=p_bundle_id;
  if v_sum<>v_expected then
    raise exception 'Settlement bundle does not reconcile: expected %, components %.',v_expected,v_sum using errcode='23514';
  end if;
  update atlas.financial_settlement_bundles set bundle_state='reconciled',updated_at=now() where id=p_bundle_id;
  return jsonb_build_object('contractVersion','financial_settlement_bundle_reconciliation_v1','bundleId',p_bundle_id,'bundleState','reconciled','expectedNetAmount',v_expected,'componentNetAmount',v_sum);
end;
$$;
revoke all on function atlas.reconcile_financial_settlement_bundle_self_api_v1(uuid) from public,anon;
grant execute on function atlas.reconcile_financial_settlement_bundle_self_api_v1(uuid) to authenticated;

create or replace function atlas.link_financial_obligation_resource_self_api_v1(
  p_obligation_id uuid,
  p_resource_pool_id uuid,
  p_resource_interest_id uuid,
  p_relation_kind text,
  p_provenance jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_book uuid;
  v_pool_book uuid;
  v_row atlas.financial_obligation_resource_links%rowtype;
begin
  select accounting_book_id into v_book from atlas.financial_obligations where id=p_obligation_id;
  select accounting_book_id into v_pool_book from atlas.accounting_resource_pools where id=p_resource_pool_id;
  if v_book is null or v_pool_book is null or v_book<>v_pool_book then raise exception 'Obligation and resource pool must share an accounting book.' using errcode='23514'; end if;
  if not atlas.accounting_book_authorized_self_v1(v_book) then raise exception 'Accounting book authority required.' using errcode='42501'; end if;
  if p_resource_interest_id is not null and not exists(select 1 from atlas.accounting_resource_interests where id=p_resource_interest_id and resource_pool_id=p_resource_pool_id) then
    raise exception 'Resource interest must belong to the linked resource pool.' using errcode='23514';
  end if;
  if p_provenance is null or jsonb_typeof(p_provenance)<>'object' or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then raise exception 'Resource link provenance and metadata must be JSON objects.' using errcode='22023'; end if;
  insert into atlas.financial_obligation_resource_links(obligation_id,resource_pool_id,resource_interest_id,relation_kind,provenance,metadata)
  values(p_obligation_id,p_resource_pool_id,p_resource_interest_id,lower(btrim(coalesce(p_relation_kind,''))),p_provenance||jsonb_build_object('authority','link_financial_obligation_resource_self_api_v1'),p_metadata)
  returning * into v_row;
  return jsonb_build_object('contractVersion','financial_obligation_resource_link_v1','resourceLinkId',v_row.id,'obligationId',v_row.obligation_id,'resourcePoolId',v_row.resource_pool_id,'resourceInterestId',v_row.resource_interest_id,'relationKind',v_row.relation_kind);
end;
$$;
revoke all on function atlas.link_financial_obligation_resource_self_api_v1(uuid,uuid,uuid,text,jsonb,jsonb) from public,anon;
grant execute on function atlas.link_financial_obligation_resource_self_api_v1(uuid,uuid,uuid,text,jsonb,jsonb) to authenticated;
