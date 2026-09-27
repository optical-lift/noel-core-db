-- Atlas financial source movement reconciliation hardening v1
--
-- Makes the source-movement write membrane safely idempotent under retries and concurrency.
-- Existing confirmed matches are compared before capacity accounting, so replay does not count
-- its own allocation twice. Different match keys sharing source rows serialize on those rows.

create or replace function atlas.reconcile_financial_source_movement_self_api_v1(
  p_match_key text,
  p_movement_on date,
  p_currency text,
  p_members jsonb,
  p_provenance jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_principal uuid;
  v_key text:=btrim(coalesce(p_match_key,''));
  v_currency text:=upper(btrim(coalesce(p_currency,'')));
  v_outflow numeric;
  v_inflow numeric;
  v_match atlas.financial_source_movement_matches%rowtype;
  v_existing_members jsonb;
  v_requested_members jsonb;
  v_member jsonb;
  v_transaction_id uuid;
  v_role text;
  v_amount numeric;
  v_source_amount numeric;
  v_transaction_currency text;
  v_transaction_state text;
  v_connected_source_id uuid;
  v_already_matched numeric;
  v_inserted boolean:=false;
begin
  if auth.uid() is null then
    raise exception 'Authentication required.' using errcode='42501';
  end if;

  v_principal:=atlas.current_principal_id_v1();
  if v_principal is null then
    raise exception 'Canonical Principal context required.' using errcode='42501';
  end if;

  if v_key='' or p_movement_on is null or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Movement match key, date, and three-letter currency are required.' using errcode='22023';
  end if;
  if p_members is null or jsonb_typeof(p_members)<>'array' or jsonb_array_length(p_members)<2 then
    raise exception 'At least two source transaction members are required.' using errcode='22023';
  end if;
  if p_provenance is null or jsonb_typeof(p_provenance)<>'object'
     or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Movement provenance and metadata must be JSON objects.' using errcode='22023';
  end if;

  -- Validate textual representations before any casts so malformed client JSON fails as input,
  -- not as an incidental database cast error.
  if exists (
    select 1
    from jsonb_array_elements(p_members) item
    where jsonb_typeof(item)<>'object'
       or coalesce(item->>'financialTransactionId','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       or lower(btrim(coalesce(item->>'movementRole',''))) not in ('outflow','inflow')
       or coalesce(item->>'matchedAmount','') !~ '^[0-9]+([.][0-9]+)?$'
       or (item->>'matchedAmount')::numeric<=0
  ) then
    raise exception 'Each movement member requires a UUID financialTransactionId, outflow/inflow role, and positive matchedAmount.' using errcode='22023';
  end if;

  select jsonb_agg(
    jsonb_build_object(
      'financialTransactionId',(item->>'financialTransactionId')::uuid,
      'movementRole',lower(btrim(item->>'movementRole')),
      'matchedAmount',(item->>'matchedAmount')::numeric
    ) order by (item->>'financialTransactionId')::uuid
  ) into v_requested_members
  from jsonb_array_elements(p_members) item;

  if (select count(*) from jsonb_array_elements(p_members)) <>
     (select count(distinct (item->>'financialTransactionId')::uuid) from jsonb_array_elements(p_members) item) then
    raise exception 'A source transaction may appear only once in one movement match.' using errcode='22023';
  end if;

  select coalesce(sum((item->>'matchedAmount')::numeric),0) into v_outflow
  from jsonb_array_elements(p_members) item
  where lower(btrim(item->>'movementRole'))='outflow';
  select coalesce(sum((item->>'matchedAmount')::numeric),0) into v_inflow
  from jsonb_array_elements(p_members) item
  where lower(btrim(item->>'movementRole'))='inflow';

  if v_outflow<=0 or v_inflow<=0 or v_outflow<>v_inflow then
    raise exception 'Confirmed source movement must contain balanced outflow and inflow matched amounts.' using errcode='23514';
  end if;

  -- Serialize retries/concurrent creation for the same principal + stable key.
  perform pg_advisory_xact_lock(hashtextextended(
    'atlas.financial_source_movement:'||v_principal::text||':'||v_key,
    0
  ));

  select * into v_match
  from atlas.financial_source_movement_matches movement
  where movement.created_by_principal_id=v_principal
    and movement.match_key=v_key
  for update;

  if v_match.id is not null then
    select jsonb_agg(
      jsonb_build_object(
        'financialTransactionId',member.financial_transaction_id,
        'movementRole',member.movement_role,
        'matchedAmount',member.matched_amount
      ) order by member.financial_transaction_id
    ) into v_existing_members
    from atlas.financial_source_movement_match_members member
    where member.movement_match_id=v_match.id;

    if v_match.movement_on<>p_movement_on
       or v_match.currency<>v_currency
       or v_match.movement_amount<>v_outflow
       or v_match.match_state<>'confirmed'
       or coalesce(v_existing_members,'[]'::jsonb)<>coalesce(v_requested_members,'[]'::jsonb) then
      raise exception 'Movement match key already exists with different immutable source facts.' using errcode='23505';
    end if;

    -- Idempotent replay still requires present authority over every source represented by the match.
    for v_connected_source_id in
      select distinct transaction.connected_source_id
      from atlas.financial_source_movement_match_members member
      join atlas.financial_source_transactions transaction
        on transaction.id=member.financial_transaction_id
      where member.movement_match_id=v_match.id
    loop
      if not atlas.financial_connected_source_authorized_self_v1(v_connected_source_id) then
        raise exception 'Authority over every reconciled financial source is required.' using errcode='42501';
      end if;
    end loop;

    return jsonb_build_object(
      'contractVersion','financial_source_movement_match_v1',
      'movementMatchId',v_match.id,
      'created',false,
      'matchKey',v_match.match_key,
      'movementOn',v_match.movement_on,
      'movementAmount',v_match.movement_amount,
      'currency',v_match.currency,
      'matchState',v_match.match_state,
      'members',v_requested_members,
      'truthBoundary',jsonb_build_object(
        'sourceRowsMerged',false,
        'economicMeaningEstablished',false,
        'obligationSettlementEstablished',false,
        'accountingTreatmentEstablished',false,
        'journalPosted',false
      )
    );
  end if;

  -- Serialize all source rows in deterministic UUID order. This prevents two different match keys
  -- from simultaneously consuming the same unmatched transaction capacity.
  perform 1
  from atlas.financial_source_transactions transaction
  where transaction.id in (
    select (item->>'financialTransactionId')::uuid
    from jsonb_array_elements(p_members) item
  )
  order by transaction.id
  for update;

  for v_member in select item from jsonb_array_elements(p_members) item loop
    v_transaction_id:=(v_member->>'financialTransactionId')::uuid;
    v_role:=lower(btrim(v_member->>'movementRole'));
    v_amount:=(v_member->>'matchedAmount')::numeric;

    select transaction.source_amount,
           transaction.currency,
           transaction.transaction_state,
           transaction.connected_source_id
      into v_source_amount,
           v_transaction_currency,
           v_transaction_state,
           v_connected_source_id
    from atlas.financial_source_transactions transaction
    where transaction.id=v_transaction_id;

    if v_connected_source_id is null then
      raise exception 'Source transaction not found.' using errcode='23503';
    end if;
    if not atlas.financial_connected_source_authorized_self_v1(v_connected_source_id) then
      raise exception 'Authority over every reconciled financial source is required.' using errcode='42501';
    end if;
    if v_transaction_state<>'observed' then
      raise exception 'Only observed source transactions may be reconciled.' using errcode='23514';
    end if;
    if v_transaction_currency<>v_currency then
      raise exception 'All movement members must share one currency.' using errcode='23514';
    end if;
    if (v_role='outflow' and v_source_amount>=0)
       or (v_role='inflow' and v_source_amount<=0) then
      raise exception 'Movement role must agree with the normalized source amount sign.' using errcode='23514';
    end if;
    if v_amount>abs(v_source_amount) then
      raise exception 'Matched amount may not exceed its source transaction magnitude.' using errcode='23514';
    end if;

    select coalesce(sum(member.matched_amount),0) into v_already_matched
    from atlas.financial_source_movement_match_members member
    join atlas.financial_source_movement_matches movement
      on movement.id=member.movement_match_id
     and movement.match_state='confirmed'
    where member.financial_transaction_id=v_transaction_id;

    if v_already_matched+v_amount>abs(v_source_amount) then
      raise exception 'Confirmed movement matches may not over-allocate a source transaction.' using errcode='23514';
    end if;
  end loop;

  insert into atlas.financial_source_movement_matches(
    created_by_principal_id,
    match_key,
    movement_on,
    movement_amount,
    currency,
    match_state,
    provenance,
    metadata,
    created_by_user_id
  ) values (
    v_principal,
    v_key,
    p_movement_on,
    v_outflow,
    v_currency,
    'confirmed',
    p_provenance||jsonb_build_object(
      'authority','reconcile_financial_source_movement_self_api_v1',
      'economicMeaningEstablished',false,
      'obligationSettlementEstablished',false,
      'journalPosted',false
    ),
    p_metadata,
    auth.uid()
  ) returning * into v_match;
  v_inserted:=true;

  insert into atlas.financial_source_movement_match_members(
    movement_match_id,
    financial_transaction_id,
    movement_role,
    matched_amount,
    provenance
  )
  select v_match.id,
         (item->>'financialTransactionId')::uuid,
         lower(btrim(item->>'movementRole')),
         (item->>'matchedAmount')::numeric,
         jsonb_build_object('authority','reconcile_financial_source_movement_self_api_v1')
  from jsonb_array_elements(p_members) item;

  return jsonb_build_object(
    'contractVersion','financial_source_movement_match_v1',
    'movementMatchId',v_match.id,
    'created',v_inserted,
    'matchKey',v_match.match_key,
    'movementOn',v_match.movement_on,
    'movementAmount',v_match.movement_amount,
    'currency',v_match.currency,
    'matchState',v_match.match_state,
    'members',v_requested_members,
    'truthBoundary',jsonb_build_object(
      'sourceRowsMerged',false,
      'economicMeaningEstablished',false,
      'obligationSettlementEstablished',false,
      'accountingTreatmentEstablished',false,
      'journalPosted',false
    )
  );
end;
$$;

revoke all on function atlas.reconcile_financial_source_movement_self_api_v1(text,date,text,jsonb,jsonb,jsonb)
  from public,anon;
grant execute on function atlas.reconcile_financial_source_movement_self_api_v1(text,date,text,jsonb,jsonb,jsonb)
  to authenticated;
