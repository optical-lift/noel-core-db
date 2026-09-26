-- Credit-capacity hardening after inflow review exists.
-- A source credit already consumed by an Organization Receipt or commercial
-- reconciliation cannot also be confirmed as a transfer.

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

  select
    coalesce((select sum(r.amount) from atlas.financial_transfer_reconciliations r where r.from_transaction_id=v_from.id and r.reconciliation_state='confirmed'),0)
    + coalesce((select sum(a.allocated_amount) from atlas.financial_transaction_allocations a where a.transaction_id=v_from.id and a.allocation_state='active'),0)
  into v_from_used;

  select
    coalesce((select sum(r.amount) from atlas.financial_transfer_reconciliations r where r.to_transaction_id=v_to.id and r.reconciliation_state='confirmed'),0)
    + coalesce((select sum(a.allocated_amount) from atlas.financial_inflow_allocations a where a.transaction_id=v_to.id and a.allocation_state='active'),0)
    + coalesce((select sum(r.amount) from atlas.financial_commercial_reconciliations r where r.financial_source_transaction_id=v_to.id and r.reconciliation_state='confirmed'),0)
  into v_to_used;

  if v_from_used+p_amount>v_from.amount or v_to_used+p_amount>v_to.amount then
    raise exception 'Transfer amount exceeds unresolved source capacity.' using errcode='23514';
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
      'expenseCreated',false,
      'incomeCreated',false,
      'sourceEvidenceMutated',false,
      'transferMeaningHumanConfirmed',true,
      'creditCapacityCannotBeDoubleUsed',true
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
    'contractVersion','financial_transfer_candidates_self_v2',
    'startOn',p_start_on,
    'endOn',p_end_on,
    'maxDayDistance',p_max_day_distance,
    'items',coalesce((
      with debit_remaining as (
        select d.*,
          d.amount
          - coalesce((select sum(r.amount) from atlas.financial_transfer_reconciliations r where r.from_transaction_id=d.id and r.reconciliation_state='confirmed'),0)
          - coalesce((select sum(a.allocated_amount) from atlas.financial_transaction_allocations a where a.transaction_id=d.id and a.allocation_state='active'),0) as remaining_amount
        from atlas.financial_source_transactions d
        where d.direction='debit'
          and d.truth_state='observed'
          and d.transaction_date between p_start_on and p_end_on
          and atlas.financial_source_authorized_self_v1(d.connected_source_id)
      ),
      credit_remaining as (
        select c.*,
          c.amount
          - coalesce((select sum(r.amount) from atlas.financial_transfer_reconciliations r where r.to_transaction_id=c.id and r.reconciliation_state='confirmed'),0)
          - coalesce((select sum(a.allocated_amount) from atlas.financial_inflow_allocations a where a.transaction_id=c.id and a.allocation_state='active'),0)
          - coalesce((select sum(r.amount) from atlas.financial_commercial_reconciliations r where r.financial_source_transaction_id=c.id and r.reconciliation_state='confirmed'),0) as remaining_amount
        from atlas.financial_source_transactions c
        where c.direction='credit'
          and c.truth_state='observed'
          and c.transaction_date between p_start_on-p_max_day_distance and p_end_on+p_max_day_distance
          and atlas.financial_source_authorized_self_v1(c.connected_source_id)
      )
      select jsonb_agg(jsonb_build_object(
        'fromTransactionId',d.id,
        'toTransactionId',c.id,
        'amount',d.remaining_amount,
        'currency',d.currency,
        'dayDistance',abs(d.transaction_date-c.transaction_date),
        'fromDate',d.transaction_date,
        'toDate',c.transaction_date,
        'fromDescription',d.description,
        'toDescription',c.description,
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
      'merchantTextNotUsedAsAuthority',true,
      'alreadyAllocatedOrCommerciallyReconciledCreditExcluded',true
    )
  );
end;
$function$;

comment on function atlas.confirm_financial_transfer_self_api_v1(uuid,uuid,numeric,text,text,jsonb) is
  'Confirms one movement between source transactions only within unresolved capacity. Credit amounts already allocated or commercially reconciled cannot also become transfers.';
comment on function atlas.financial_transfer_candidates_self_api_v1(date,date,integer) is
  'Read-only structural transfer candidates over unresolved debit and credit capacity. Existing inflow allocations and commercial reconciliations reduce credit capacity before matching.';