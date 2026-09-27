-- Atlas financial obligation + settlement read models v1.
-- Read-only economic position. These functions do not classify, recognize, settle, or post anything.

create or replace function atlas.financial_obligation_position_self_api_v1(p_obligation_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_obligation atlas.financial_obligations%rowtype;
  v_reporting_entity_id uuid;
  v_applied numeric;
  v_capacity text;
begin
  select * into v_obligation from atlas.financial_obligations where id=p_obligation_id;
  if v_obligation.id is null then raise exception 'Financial obligation not found.' using errcode='P0002'; end if;
  if not atlas.accounting_book_authorized_self_v1(v_obligation.accounting_book_id) then raise exception 'Accounting book authority required.' using errcode='42501'; end if;
  select reporting_entity_id into v_reporting_entity_id from atlas.accounting_books where id=v_obligation.accounting_book_id;
  select coalesce(sum(a.applied_amount),0) into v_applied
  from atlas.financial_settlement_allocations a
  join atlas.financial_settlements s on s.id=a.settlement_id and s.settlement_state='confirmed'
  where a.obligation_id=p_obligation_id;

  v_capacity:=case
    when exists(select 1 from atlas.financial_obligation_parties p where p.obligation_id=p_obligation_id and p.entity_id=v_reporting_entity_id and p.role_kind='obligor') then 'payable'
    when exists(select 1 from atlas.financial_obligation_parties p where p.obligation_id=p_obligation_id and p.entity_id=v_reporting_entity_id and p.role_kind='obligee') then 'receivable'
    else 'administered'
  end;

  return jsonb_build_object(
    'contractVersion','financial_obligation_position_v1',
    'obligationId',v_obligation.id,
    'accountingBookId',v_obligation.accounting_book_id,
    'reportingEntityId',v_reporting_entity_id,
    'bookCapacity',v_capacity,
    'obligationKey',v_obligation.obligation_key,
    'obligationKind',v_obligation.obligation_kind,
    'faceAmount',v_obligation.face_amount,
    'confirmedSettlementAmount',v_applied,
    'remainingAmount',greatest(v_obligation.face_amount-v_applied,0),
    'currency',v_obligation.currency,
    'incurredOn',v_obligation.incurred_on,
    'dueOn',v_obligation.due_on,
    'settlementState',v_obligation.settlement_state,
    'conditionState',v_obligation.condition_state,
    'entitlementState',v_obligation.entitlement_state,
    'refundabilityState',v_obligation.refundability_state,
    'parties',coalesce((
      select jsonb_agg(jsonb_build_object(
        'entityId',e.id,'displayName',e.display_name,'entityKind',e.entity_kind,'roleKind',p.role_kind
      ) order by p.role_kind,e.display_name,e.id)
      from atlas.financial_obligation_parties p
      join reality.entities e on e.id=p.entity_id and e.identity_state='canonical'
      where p.obligation_id=p_obligation_id
    ),'[]'::jsonb),
    'settlementAllocations',coalesce((
      select jsonb_agg(jsonb_build_object(
        'allocationId',a.id,'settlementId',s.id,'settlementKey',s.settlement_key,'settlementOn',s.settlement_on,
        'settlementKind',s.settlement_kind,'allocationKind',a.allocation_kind,'appliedAmount',a.applied_amount,
        'currency',a.currency,'settlementState',s.settlement_state
      ) order by s.settlement_on,s.id,a.id)
      from atlas.financial_settlement_allocations a
      join atlas.financial_settlements s on s.id=a.settlement_id
      where a.obligation_id=p_obligation_id
    ),'[]'::jsonb),
    'stateEvents',coalesce((
      select jsonb_agg(jsonb_build_object(
        'stateEventId',ev.id,'eventKey',ev.event_key,'eventOn',ev.event_on,'eventKind',ev.event_kind,
        'eventAmount',ev.event_amount,'evidenceRecordId',ev.evidence_record_id
      ) order by ev.event_on,ev.created_at,ev.id)
      from atlas.financial_obligation_state_events ev where ev.obligation_id=p_obligation_id
    ),'[]'::jsonb),
    'resourceLinks',coalesce((
      select jsonb_agg(jsonb_build_object(
        'resourceLinkId',rl.id,'resourcePoolId',rl.resource_pool_id,'resourceInterestId',rl.resource_interest_id,
        'relationKind',rl.relation_kind
      ) order by rl.id)
      from atlas.financial_obligation_resource_links rl where rl.obligation_id=p_obligation_id
    ),'[]'::jsonb),
    'truthBoundary',jsonb_build_object(
      'sourceMovementIsSeparateEvidence',true,
      'settlementIsNotRevenueRecognition',true,
      'journalPostingIsSeparate',true
    )
  );
end;
$$;
revoke all on function atlas.financial_obligation_position_self_api_v1(uuid) from public,anon;
grant execute on function atlas.financial_obligation_position_self_api_v1(uuid) to authenticated;

create or replace function atlas.financial_open_obligations_self_api_v1(
  p_accounting_book_id uuid,
  p_as_of date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_reporting_entity_id uuid;
begin
  if not atlas.accounting_book_authorized_self_v1(p_accounting_book_id) then raise exception 'Accounting book authority required.' using errcode='42501'; end if;
  select reporting_entity_id into v_reporting_entity_id from atlas.accounting_books where id=p_accounting_book_id;
  return jsonb_build_object(
    'contractVersion','financial_open_obligations_v1',
    'accountingBookId',p_accounting_book_id,
    'reportingEntityId',v_reporting_entity_id,
    'asOf',p_as_of,
    'items',coalesce((
      select jsonb_agg(jsonb_build_object(
        'obligationId',o.id,
        'obligationKey',o.obligation_key,
        'obligationKind',o.obligation_kind,
        'bookCapacity',case
          when exists(select 1 from atlas.financial_obligation_parties p where p.obligation_id=o.id and p.entity_id=v_reporting_entity_id and p.role_kind='obligor') then 'payable'
          when exists(select 1 from atlas.financial_obligation_parties p where p.obligation_id=o.id and p.entity_id=v_reporting_entity_id and p.role_kind='obligee') then 'receivable'
          else 'administered'
        end,
        'faceAmount',o.face_amount,
        'settledAmount',coalesce(a.applied,0),
        'remainingAmount',greatest(o.face_amount-coalesce(a.applied,0),0),
        'currency',o.currency,
        'incurredOn',o.incurred_on,
        'dueOn',o.due_on,
        'overdue',o.due_on is not null and o.due_on<p_as_of,
        'conditionState',o.condition_state,
        'entitlementState',o.entitlement_state,
        'refundabilityState',o.refundability_state,
        'settlementState',o.settlement_state,
        'obligorEntityId',(select p.entity_id from atlas.financial_obligation_parties p where p.obligation_id=o.id and p.role_kind='obligor' order by p.id limit 1),
        'obligeeEntityId',(select p.entity_id from atlas.financial_obligation_parties p where p.obligation_id=o.id and p.role_kind='obligee' order by p.id limit 1)
      ) order by o.due_on nulls last,o.incurred_on,o.id)
      from atlas.financial_obligations o
      left join lateral (
        select sum(sa.applied_amount) as applied
        from atlas.financial_settlement_allocations sa
        join atlas.financial_settlements s on s.id=sa.settlement_id and s.settlement_state='confirmed'
        where sa.obligation_id=o.id
      ) a on true
      where o.accounting_book_id=p_accounting_book_id
        and o.incurred_on<=p_as_of
        and o.settlement_state in ('open','partially_settled')
    ),'[]'::jsonb),
    'truthBoundary',jsonb_build_object('readOnly',true,'journalPosted',false)
  );
end;
$$;
revoke all on function atlas.financial_open_obligations_self_api_v1(uuid,date) from public,anon;
grant execute on function atlas.financial_open_obligations_self_api_v1(uuid,date) to authenticated;

create or replace function atlas.financial_settlement_position_self_api_v1(p_settlement_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_settlement atlas.financial_settlements%rowtype;
  v_allocated numeric;
begin
  select * into v_settlement from atlas.financial_settlements where id=p_settlement_id;
  if v_settlement.id is null then raise exception 'Financial settlement not found.' using errcode='P0002'; end if;
  if not atlas.accounting_book_authorized_self_v1(v_settlement.accounting_book_id) then raise exception 'Accounting book authority required.' using errcode='42501'; end if;
  select coalesce(sum(applied_amount),0) into v_allocated from atlas.financial_settlement_allocations where settlement_id=p_settlement_id;
  return jsonb_build_object(
    'contractVersion','financial_settlement_position_v1',
    'settlementId',v_settlement.id,
    'accountingBookId',v_settlement.accounting_book_id,
    'settlementKey',v_settlement.settlement_key,
    'settlementOn',v_settlement.settlement_on,
    'settlementKind',v_settlement.settlement_kind,
    'amount',v_settlement.amount,
    'allocatedAmount',v_allocated,
    'unallocatedAmount',greatest(v_settlement.amount-v_allocated,0),
    'currency',v_settlement.currency,
    'mediumKind',v_settlement.medium_kind,
    'settlementState',v_settlement.settlement_state,
    'roles',coalesce((
      select jsonb_agg(jsonb_build_object('entityId',e.id,'displayName',e.display_name,'entityKind',e.entity_kind,'roleKind',r.role_kind)
        order by r.role_kind,e.display_name,e.id)
      from atlas.financial_settlement_roles r
      join reality.entities e on e.id=r.entity_id and e.identity_state='canonical'
      where r.settlement_id=p_settlement_id
    ),'[]'::jsonb),
    'sourceLinks',coalesce((
      select jsonb_agg(jsonb_build_object(
        'sourceDomain',sl.source_domain,'sourceKind',sl.source_kind,'sourceId',sl.source_id,
        'relationKind',sl.relation_kind,'evidenceRecordId',sl.evidence_record_id
      ) order by sl.id)
      from atlas.financial_settlement_source_links sl where sl.settlement_id=p_settlement_id
    ),'[]'::jsonb),
    'allocations',coalesce((
      select jsonb_agg(jsonb_build_object(
        'allocationId',a.id,'obligationId',a.obligation_id,'obligationKey',o.obligation_key,
        'allocationKind',a.allocation_kind,'appliedAmount',a.applied_amount,'currency',a.currency
      ) order by a.id)
      from atlas.financial_settlement_allocations a
      join atlas.financial_obligations o on o.id=a.obligation_id
      where a.settlement_id=p_settlement_id
    ),'[]'::jsonb),
    'lineage',jsonb_build_object(
      'parents',coalesce((select jsonb_agg(jsonb_build_object('settlementId',l.parent_settlement_id,'relationKind',l.relation_kind) order by l.id) from atlas.financial_settlement_lineage l where l.child_settlement_id=p_settlement_id),'[]'::jsonb),
      'children',coalesce((select jsonb_agg(jsonb_build_object('settlementId',l.child_settlement_id,'relationKind',l.relation_kind) order by l.id) from atlas.financial_settlement_lineage l where l.parent_settlement_id=p_settlement_id),'[]'::jsonb)
    ),
    'truthBoundary',jsonb_build_object('sourceTransactionCopied',false,'journalPostingIsSeparate',true)
  );
end;
$$;
revoke all on function atlas.financial_settlement_position_self_api_v1(uuid) from public,anon;
grant execute on function atlas.financial_settlement_position_self_api_v1(uuid) to authenticated;

create or replace function atlas.financial_counterparty_position_self_api_v1(
  p_accounting_book_id uuid,
  p_entity_id uuid,
  p_as_of date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_reporting_entity_id uuid;
begin
  if not atlas.accounting_book_authorized_self_v1(p_accounting_book_id) then raise exception 'Accounting book authority required.' using errcode='42501'; end if;
  if not exists(select 1 from reality.entities where id=p_entity_id and identity_state='canonical') then raise exception 'Canonical Reality counterparty required.' using errcode='23503'; end if;
  select reporting_entity_id into v_reporting_entity_id from atlas.accounting_books where id=p_accounting_book_id;
  return jsonb_build_object(
    'contractVersion','financial_counterparty_position_v1',
    'accountingBookId',p_accounting_book_id,
    'reportingEntityId',v_reporting_entity_id,
    'counterpartyEntityId',p_entity_id,
    'asOf',p_as_of,
    'openObligations',coalesce((
      select jsonb_agg(jsonb_build_object(
        'obligationId',o.id,'obligationKey',o.obligation_key,'obligationKind',o.obligation_kind,
        'counterpartyRole',p.role_kind,'faceAmount',o.face_amount,'settledAmount',coalesce(a.applied,0),
        'remainingAmount',greatest(o.face_amount-coalesce(a.applied,0),0),'currency',o.currency,
        'dueOn',o.due_on,'settlementState',o.settlement_state
      ) order by o.due_on nulls last,o.incurred_on,o.id)
      from atlas.financial_obligation_parties p
      join atlas.financial_obligations o on o.id=p.obligation_id
      left join lateral (
        select sum(sa.applied_amount) as applied
        from atlas.financial_settlement_allocations sa
        join atlas.financial_settlements s on s.id=sa.settlement_id and s.settlement_state='confirmed'
        where sa.obligation_id=o.id
      ) a on true
      where o.accounting_book_id=p_accounting_book_id and p.entity_id=p_entity_id
        and o.incurred_on<=p_as_of and o.settlement_state in ('open','partially_settled')
    ),'[]'::jsonb),
    'truthBoundary',jsonb_build_object('canonicalCounterparty',true,'readOnly',true)
  );
end;
$$;
revoke all on function atlas.financial_counterparty_position_self_api_v1(uuid,uuid,date) from public,anon;
grant execute on function atlas.financial_counterparty_position_self_api_v1(uuid,uuid,date) to authenticated;
