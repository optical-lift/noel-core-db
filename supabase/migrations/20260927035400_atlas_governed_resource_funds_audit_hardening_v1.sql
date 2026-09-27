-- Audit hardening for governed resources/custody v1.

create or replace function atlas.guard_accounting_resource_constraint_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_posture text;
  v_identity_state text;
  v_has_posted_activity boolean:=false;
begin
  select governance_posture into v_posture from atlas.accounting_resource_pools where id=new.resource_pool_id;
  if v_posture is null then raise exception 'Resource pool not found.' using errcode='23503'; end if;

  if new.imposed_by_entity_id is not null then
    select identity_state into v_identity_state from reality.entities where id=new.imposed_by_entity_id;
    if v_identity_state<>'canonical' then
      raise exception 'Resource constraint party must be a canonical Reality entity.' using errcode='23514';
    end if;
  end if;

  if new.constraint_kind='legal_custody' and v_posture<>'custodial' then
    raise exception 'Legal custody constraints require a custodial resource pool.' using errcode='23514';
  end if;
  if new.constraint_kind='internal_designation' and v_posture<>'internally_designated' then
    raise exception 'Internal-designation constraints require an internally designated pool.' using errcode='23514';
  end if;
  if new.constraint_kind in ('purpose','time','purpose_and_time','perpetual') and v_posture='unrestricted' then
    raise exception 'Externally meaningful restrictions may not be attached to an unrestricted pool.' using errcode='23514';
  end if;

  if tg_op='UPDATE' then
    select exists(
      select 1
      from atlas.accounting_resource_movements m
      join atlas.accounting_journal_lines l on l.id=m.journal_line_id
      join atlas.accounting_journal_entries e on e.id=l.journal_entry_id
      where m.resource_pool_id=old.resource_pool_id and e.entry_state='posted'
    ) into v_has_posted_activity;

    if v_has_posted_activity and (
      old.resource_pool_id is distinct from new.resource_pool_id
      or old.constraint_key is distinct from new.constraint_key
      or old.constraint_kind is distinct from new.constraint_kind
      or old.imposed_by_entity_id is distinct from new.imposed_by_entity_id
      or old.purpose_text is distinct from new.purpose_text
      or old.starts_on is distinct from new.starts_on
      or old.ends_on is distinct from new.ends_on
      or old.evidence_record_id is distinct from new.evidence_record_id
      or old.rule_spec is distinct from new.rule_spec
    ) then
      raise exception 'A resource constraint with posted activity is historically frozen. Establish a superseding/release fact instead of rewriting the governing rule.' using errcode='55000';
    end if;
  end if;

  new.updated_at:=now();
  return new;
end;
$$;

-- Correct custody-interest ledger aggregation: running balances are calculated in a rowset before JSON aggregation.
create or replace function atlas.accounting_custody_interest_ledger_self_api_v1(
  p_resource_interest_id uuid,
  p_start_on date,
  p_end_on date
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_interest atlas.accounting_resource_interests%rowtype;
  v_pool atlas.accounting_resource_pools%rowtype;
  v_opening numeric:=0;
  v_activity numeric:=0;
  v_rows jsonb:='[]'::jsonb;
begin
  select * into v_interest from atlas.accounting_resource_interests where id=p_resource_interest_id;
  if v_interest.id is null then raise exception 'Resource interest not found.' using errcode='P0002'; end if;
  select * into v_pool from atlas.accounting_resource_pools where id=v_interest.resource_pool_id;
  if v_pool.id is null or v_pool.ownership_posture<>'third_party_custody' then
    raise exception 'Custodial beneficiary/client interest required.' using errcode='23514';
  end if;
  if not atlas.accounting_book_authorized_self_v1(v_pool.accounting_book_id) then raise exception 'Accounting book authority required.' using errcode='42501'; end if;
  if p_start_on is null or p_end_on is null or p_end_on<p_start_on then raise exception 'Valid custody-ledger date range required.' using errcode='22023'; end if;

  select coalesce(sum(m.amount_delta),0) into v_opening
  from atlas.accounting_resource_movements m
  join atlas.accounting_journal_lines l on l.id=m.journal_line_id
  join atlas.accounting_journal_entries e on e.id=l.journal_entry_id
  where m.resource_interest_id=v_interest.id and e.entry_state='posted' and e.entry_date<p_start_on;

  with activity as (
    select e.entry_date,e.id as journal_entry_id,l.id as journal_line_id,m.id as movement_id,
      m.movement_kind,m.amount_delta,coalesce(l.memo,e.memo) as memo,
      v_opening+sum(m.amount_delta) over(
        order by e.entry_date,e.id,m.id rows between unbounded preceding and current row
      ) as balance_after
    from atlas.accounting_resource_movements m
    join atlas.accounting_journal_lines l on l.id=m.journal_line_id
    join atlas.accounting_journal_entries e on e.id=l.journal_entry_id
    where m.resource_interest_id=v_interest.id
      and e.entry_state='posted'
      and e.entry_date between p_start_on and p_end_on
  )
  select coalesce(sum(amount_delta),0),coalesce(jsonb_agg(jsonb_build_object(
    'entryDate',entry_date,'journalEntryId',journal_entry_id,'journalLineId',journal_line_id,
    'movementKind',movement_kind,'amountDelta',amount_delta,'memo',memo,'balanceAfter',balance_after
  ) order by entry_date,journal_entry_id,movement_id),'[]'::jsonb)
  into v_activity,v_rows
  from activity;

  return jsonb_build_object(
    'contractVersion','accounting_custody_interest_ledger_v1',
    'resourcePoolId',v_pool.id,'resourceInterestId',v_interest.id,
    'holderEntityId',v_interest.holder_entity_id,'interestKind',v_interest.interest_kind,
    'ledgerId',v_interest.ledger_id,'contextKind',v_interest.context_kind,'contextKey',v_interest.context_key,
    'startOn',p_start_on,'endOn',p_end_on,'openingBalance',v_opening,
    'activity',v_rows,'closingBalance',v_opening+v_activity,
    'truthBoundary',jsonb_build_object(
      'postedEntriesOnly',true,'canonicalBeneficiaryEntityId',v_interest.holder_entity_id,
      'clientOrTenantNameCopiedIntoAccounting',false
    )
  );
end;
$$;
