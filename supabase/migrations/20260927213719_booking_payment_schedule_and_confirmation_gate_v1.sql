create table if not exists ledger.booking_payment_schedules (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references ledger.booking_requests(id) on delete cascade,
  agreement_id uuid null references ledger.booking_agreements(id) on delete set null,
  offer_snapshot_id uuid null references atlas.commercial_offer_snapshots(id) on delete set null,
  version integer not null check (version > 0),
  schedule_state text not null default 'draft' check (schedule_state in ('draft','active','superseded','void','settled')),
  total_amount numeric not null check (total_amount >= 0),
  currency text not null default 'USD' check (currency ~ '^[A-Z]{3}$'),
  basis_kind text not null check (btrim(basis_kind) <> ''),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(request_id,version)
);

create unique index if not exists booking_payment_schedules_one_active_uq
  on ledger.booking_payment_schedules(request_id)
  where schedule_state='active';

create table if not exists ledger.booking_payment_schedule_lines (
  id uuid primary key default gen_random_uuid(),
  schedule_id uuid not null references ledger.booking_payment_schedules(id) on delete cascade,
  line_key text not null check (btrim(line_key) <> ''),
  line_order integer not null default 0,
  obligation_kind text not null check (btrim(obligation_kind) <> ''),
  amount numeric not null check (amount >= 0),
  percent_of_total numeric null check (percent_of_total is null or (percent_of_total >= 0 and percent_of_total <= 100)),
  due_kind text not null default 'unresolved' check (due_kind in ('before_confirmation','fixed_at','relative_to_event','unresolved')),
  due_at timestamptz null,
  required_for_confirmation boolean not null default false,
  line_state text not null default 'active' check (line_state in ('active','waived','cancelled')),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  created_at timestamptz not null default now(),
  unique(schedule_id,line_key),
  check ((due_kind='fixed_at' and due_at is not null) or (due_kind<>'fixed_at'))
);

create table if not exists ledger.booking_payment_allocations (
  id uuid primary key default gen_random_uuid(),
  schedule_line_id uuid not null references ledger.booking_payment_schedule_lines(id) on delete cascade,
  commercial_payment_id uuid not null references atlas.commercial_payments(id) on delete restrict,
  amount_applied numeric not null check (amount_applied > 0),
  allocation_state text not null default 'applied' check (allocation_state in ('applied','reversed')),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  created_at timestamptz not null default now(),
  unique(schedule_line_id,commercial_payment_id)
);

create or replace function ledger.booking_payment_schedule_detail_v1(p_schedule_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare
  v_schedule ledger.booking_payment_schedules%rowtype;
  v_lines jsonb;
begin
  select * into v_schedule from ledger.booking_payment_schedules s where s.id=p_schedule_id;
  if v_schedule.id is null then raise exception 'Booking payment schedule not found.' using errcode='P0002'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'lineId',l.id,'lineKey',l.line_key,'lineOrder',l.line_order,
    'obligationKind',l.obligation_kind,'amount',l.amount,'percentOfTotal',l.percent_of_total,
    'dueKind',l.due_kind,'dueAt',l.due_at,'requiredForConfirmation',l.required_for_confirmation,
    'lineState',l.line_state,'creditedAmount',coalesce(a.credited_amount,0),
    'remainingAmount',greatest(l.amount-coalesce(a.credited_amount,0),0),
    'satisfied',case when l.line_state='waived' then true else coalesce(a.credited_amount,0)>=l.amount end,
    'metadata',l.metadata,'provenance',l.provenance
  ) order by l.line_order,l.line_key,l.id),'[]'::jsonb)
  into v_lines
  from ledger.booking_payment_schedule_lines l
  left join lateral (
    select coalesce(sum(pa.amount_applied),0) as credited_amount
    from ledger.booking_payment_allocations pa
    join atlas.commercial_payments cp on cp.id=pa.commercial_payment_id
    where pa.schedule_line_id=l.id and pa.allocation_state='applied' and cp.observed_state='succeeded'
  ) a on true
  where l.schedule_id=p_schedule_id;

  return jsonb_build_object(
    'contractVersion','ledger_booking_payment_schedule_v1',
    'scheduleId',v_schedule.id,'requestId',v_schedule.request_id,'agreementId',v_schedule.agreement_id,
    'offerSnapshotId',v_schedule.offer_snapshot_id,'version',v_schedule.version,
    'scheduleState',v_schedule.schedule_state,'totalAmount',v_schedule.total_amount,'currency',v_schedule.currency,
    'basisKind',v_schedule.basis_kind,'lines',v_lines,'metadata',v_schedule.metadata,'provenance',v_schedule.provenance
  );
end;
$$;

create or replace function ledger.create_booking_payment_schedule_service_v1(
  p_request_id uuid,
  p_total_amount numeric,
  p_currency text,
  p_deposit_percent numeric,
  p_deposit_required_for_confirmation boolean default true,
  p_agreement_id uuid default null,
  p_offer_snapshot_id uuid default null,
  p_basis_kind text default 'agreed_total',
  p_metadata jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_request ledger.booking_requests%rowtype;
  v_version integer;
  v_schedule_id uuid;
  v_deposit numeric;
  v_balance numeric;
begin
  if p_total_amount is null or p_total_amount < 0 then raise exception 'Payment schedule total must be >= 0.' using errcode='22023'; end if;
  if p_deposit_percent is null or p_deposit_percent < 0 or p_deposit_percent > 100 then raise exception 'Deposit percent must be between 0 and 100.' using errcode='22023'; end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then raise exception 'Currency must be a three-letter code.' using errcode='22023'; end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' or p_provenance is null or jsonb_typeof(p_provenance)<>'object' then
    raise exception 'Payment schedule metadata/provenance must be JSON objects.' using errcode='22023';
  end if;
  select * into v_request from ledger.booking_requests br where br.id=p_request_id for update;
  if v_request.id is null then raise exception 'Booking request not found.' using errcode='P0002'; end if;
  if p_agreement_id is not null and not exists(select 1 from ledger.booking_agreements a where a.id=p_agreement_id and a.request_id=p_request_id) then
    raise exception 'Agreement must belong to booking request.' using errcode='23514';
  end if;

  update ledger.booking_payment_schedules set schedule_state='superseded',updated_at=now()
  where request_id=p_request_id and schedule_state='active';

  select coalesce(max(version),0)+1 into v_version from ledger.booking_payment_schedules where request_id=p_request_id;
  v_deposit:=round((p_total_amount*p_deposit_percent/100.0)::numeric,2);
  v_balance:=round((p_total_amount-v_deposit)::numeric,2);

  insert into ledger.booking_payment_schedules(
    request_id,agreement_id,offer_snapshot_id,version,schedule_state,total_amount,currency,basis_kind,metadata,provenance
  ) values(
    p_request_id,p_agreement_id,p_offer_snapshot_id,v_version,'active',round(p_total_amount,2),p_currency,btrim(p_basis_kind),
    p_metadata||jsonb_build_object('depositPercent',p_deposit_percent,'depositRequiredForConfirmation',p_deposit_required_for_confirmation),p_provenance
  ) returning id into v_schedule_id;

  insert into ledger.booking_payment_schedule_lines(
    schedule_id,line_key,line_order,obligation_kind,amount,percent_of_total,due_kind,required_for_confirmation,metadata,provenance
  ) values(
    v_schedule_id,'deposit',10,'deposit',v_deposit,p_deposit_percent,
    case when p_deposit_required_for_confirmation then 'before_confirmation' else 'unresolved' end,
    p_deposit_required_for_confirmation,
    jsonb_build_object('calculation','round(total_amount * deposit_percent / 100, 2)'),p_provenance
  );

  if v_balance > 0 then
    insert into ledger.booking_payment_schedule_lines(
      schedule_id,line_key,line_order,obligation_kind,amount,percent_of_total,due_kind,required_for_confirmation,metadata,provenance
    ) values(
      v_schedule_id,'balance',20,'balance',v_balance,100-p_deposit_percent,'unresolved',false,
      jsonb_build_object('dueTimingState','not_established'),p_provenance
    );
  end if;

  return ledger.booking_payment_schedule_detail_v1(v_schedule_id);
end;
$$;

create or replace function ledger.allocate_booking_payment_service_v1(
  p_schedule_line_id uuid,
  p_commercial_payment_id uuid,
  p_amount_applied numeric,
  p_metadata jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_line ledger.booking_payment_schedule_lines%rowtype;
  v_schedule ledger.booking_payment_schedules%rowtype;
  v_payment atlas.commercial_payments%rowtype;
  v_existing numeric:=0;
  v_payment_existing numeric:=0;
  v_allocation_id uuid;
begin
  if p_amount_applied is null or p_amount_applied<=0 then raise exception 'Applied payment amount must be > 0.' using errcode='22023'; end if;
  select * into v_line from ledger.booking_payment_schedule_lines l where l.id=p_schedule_line_id for update;
  if v_line.id is null then raise exception 'Payment schedule line not found.' using errcode='P0002'; end if;
  select * into v_schedule from ledger.booking_payment_schedules s where s.id=v_line.schedule_id;
  if v_schedule.schedule_state<>'active' then raise exception 'Payment may only be allocated to an active schedule.' using errcode='23514'; end if;
  select * into v_payment from atlas.commercial_payments p where p.id=p_commercial_payment_id;
  if v_payment.id is null then raise exception 'Commercial payment not found.' using errcode='P0002'; end if;
  if v_payment.observed_state<>'succeeded' then raise exception 'Only succeeded commercial payments may satisfy booking obligations.' using errcode='23514'; end if;
  if v_payment.currency<>v_schedule.currency then raise exception 'Payment currency does not match schedule currency.' using errcode='23514'; end if;
  select coalesce(sum(amount_applied),0) into v_existing from ledger.booking_payment_allocations where schedule_line_id=v_line.id and allocation_state='applied';
  if v_existing+p_amount_applied>v_line.amount then raise exception 'Allocation exceeds remaining obligation amount.' using errcode='23514'; end if;
  select coalesce(sum(amount_applied),0) into v_payment_existing from ledger.booking_payment_allocations where commercial_payment_id=v_payment.id and allocation_state='applied';
  if v_payment_existing+p_amount_applied>v_payment.amount then raise exception 'Allocation exceeds unallocated payment amount.' using errcode='23514'; end if;

  insert into ledger.booking_payment_allocations(schedule_line_id,commercial_payment_id,amount_applied,metadata,provenance)
  values(v_line.id,v_payment.id,p_amount_applied,coalesce(p_metadata,'{}'::jsonb),coalesce(p_provenance,'{}'::jsonb))
  returning id into v_allocation_id;

  return jsonb_build_object('contractVersion','ledger_booking_payment_allocation_v1','allocationId',v_allocation_id,'schedule',ledger.booking_payment_schedule_detail_v1(v_schedule.id));
end;
$$;

create or replace function ledger.booking_request_payment_position_v1(p_request_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare
  v_schedule ledger.booking_payment_schedules%rowtype;
  v_detail jsonb;
  v_required integer:=0;
  v_unsatisfied integer:=0;
begin
  select * into v_schedule from ledger.booking_payment_schedules s
  where s.request_id=p_request_id and s.schedule_state='active'
  order by s.version desc,s.created_at desc,s.id desc limit 1;
  if v_schedule.id is null then
    return jsonb_build_object('contractVersion','ledger_booking_request_payment_position_v1','requestId',p_request_id,'activeSchedule',null,'confirmationRequiredLineCount',0,'unsatisfiedConfirmationLineCount',0,'confirmationPaymentsSatisfied',false);
  end if;
  v_detail:=ledger.booking_payment_schedule_detail_v1(v_schedule.id);
  select count(*),count(*) filter(where not coalesce((x->>'satisfied')::boolean,false)) into v_required,v_unsatisfied
  from jsonb_array_elements(v_detail->'lines') x
  where coalesce((x->>'requiredForConfirmation')::boolean,false) and x->>'lineState'='active';
  return jsonb_build_object(
    'contractVersion','ledger_booking_request_payment_position_v1','requestId',p_request_id,
    'activeSchedule',v_detail,'confirmationRequiredLineCount',v_required,
    'unsatisfiedConfirmationLineCount',v_unsatisfied,
    'confirmationPaymentsSatisfied',case when v_required>0 then v_unsatisfied=0 else false end
  );
end;
$$;

create or replace function ledger.booking_request_commitment_evaluation_v1(p_request_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare
  v_request ledger.booking_requests%rowtype;
  v_agreement_required boolean:=false;
  v_payment_required boolean:=false;
  v_deposit_percent numeric:=null;
  v_agreement ledger.booking_agreements%rowtype;
  v_payment_position jsonb;
  v_ready boolean:=false;
  v_unmet jsonb:='[]'::jsonb;
  v_active_holds integer:=0;
begin
  select * into v_request from ledger.booking_requests br where br.id=p_request_id;
  if v_request.id is null then raise exception 'Booking request not found.' using errcode='P0002'; end if;

  select
    coalesce(bool_or(coalesce((p.config->>'agreementRequired')::boolean,false)),false),
    coalesce(bool_or(coalesce((p.config->>'paymentRequiredBeforeConfirmation')::boolean,false)),false),
    max(case when p.config ? 'depositPercent' then (p.config->>'depositPercent')::numeric end)
  into v_agreement_required,v_payment_required,v_deposit_percent
  from ledger.booking_policies p
  where p.ledger_id=v_request.ledger_id and p.policy_state='active'
    and p.policy_kind='commitment'
    and (p.booking_kind is null or p.booking_kind=v_request.booking_kind);

  select * into v_agreement
  from ledger.booking_agreements a
  where a.request_id=p_request_id and a.agreement_state not in ('superseded','void')
  order by a.version desc,a.created_at desc,a.id desc limit 1;

  select count(*) into v_active_holds
  from ledger.booking_request_holds h
  where h.request_id=p_request_id and h.hold_state='active' and h.expires_at>now();

  v_payment_position:=ledger.booking_request_payment_position_v1(p_request_id);

  if v_request.request_state<>'approved' and v_request.request_state<>'converted' then
    v_unmet:=v_unmet||jsonb_build_array(jsonb_build_object('reasonCode','request_not_approved','requestState',v_request.request_state));
  end if;
  if v_agreement_required and (v_agreement.id is null or v_agreement.agreement_state<>'executed') then
    v_unmet:=v_unmet||jsonb_build_array(jsonb_build_object('reasonCode','executed_agreement_required','agreementId',v_agreement.id,'agreementState',v_agreement.agreement_state));
  end if;
  if v_payment_required then
    if v_payment_position->'activeSchedule'='null'::jsonb then
      v_unmet:=v_unmet||jsonb_build_array(jsonb_build_object('reasonCode','payment_schedule_required','depositPercent',v_deposit_percent));
    elsif not coalesce((v_payment_position->>'confirmationPaymentsSatisfied')::boolean,false) then
      v_unmet:=v_unmet||jsonb_build_array(jsonb_build_object('reasonCode','confirmation_payment_unsatisfied','paymentPosition',v_payment_position));
    end if;
  end if;

  v_ready:=jsonb_array_length(v_unmet)=0;

  return jsonb_build_object(
    'contractVersion','ledger_booking_request_commitment_evaluation_v2',
    'requestId',v_request.id,'requestState',v_request.request_state,'bookingKind',v_request.booking_kind,
    'agreementRequired',v_agreement_required,
    'paymentRequiredBeforeConfirmation',v_payment_required,'depositPercent',v_deposit_percent,
    'currentAgreement',case when v_agreement.id is null then null else ledger.booking_agreement_detail_v1(v_agreement.id) end,
    'paymentPosition',v_payment_position,'activeHoldCount',v_active_holds,
    'readyForConfirmation',v_ready,'unmetRequirements',v_unmet,
    'truthBoundary',jsonb_build_object('holdIsNotBooking',true,'approvalIsNotAgreement',true,'agreementIsNotPayment',true,'paymentAllocationRequiresSucceededCommercialPayment',true)
  );
end;
$$;

create or replace function ledger.materialize_booking_request_service_v1(p_request_id uuid, p_occurrence_id uuid, p_created_by_seat_id uuid, p_provenance jsonb default '{}'::jsonb, p_idempotency_key text default null::text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_request ledger.booking_requests%rowtype;
  v_occurrence_id uuid;
  v_claims jsonb;
  v_bundle jsonb;
  v_commitment jsonb;
begin
  select * into v_request from ledger.booking_requests br where br.id=p_request_id for update;
  if v_request.id is null then raise exception 'Booking request not found.' using errcode='P0002'; end if;
  if v_request.request_state='converted' and v_request.converted_booking_id is not null then
    return jsonb_build_object('contractVersion','ledger_booking_request_materialization_v2','request',ledger.booking_request_detail_v1(p_request_id),'bookingId',v_request.converted_booking_id,'alreadyConverted',true);
  end if;
  if v_request.request_state<>'approved' then raise exception 'Booking request must be approved before materialization.' using errcode='23514'; end if;

  v_commitment:=ledger.booking_request_commitment_evaluation_v1(p_request_id);
  if not coalesce((v_commitment->>'readyForConfirmation')::boolean,false) then
    raise exception 'Booking request commitment requirements are not satisfied: %',v_commitment using errcode='23514';
  end if;

  v_occurrence_id:=coalesce(v_request.occurrence_id,p_occurrence_id);
  if v_occurrence_id is null then raise exception 'Approved request requires a canonical occurrence before booking materialization.' using errcode='23514'; end if;
  if v_request.occurrence_id is not null and p_occurrence_id is not null and v_request.occurrence_id<>p_occurrence_id then
    raise exception 'Materialization occurrence does not match the approved request occurrence.' using errcode='23514';
  end if;
  if not exists(select 1 from local_intel.occurrences o where o.id=v_occurrence_id) then raise exception 'Canonical occurrence not found.' using errcode='P0002'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'resourceId',rr.resource_id,'claimKind',rr.claim_kind,'startsAt',rr.starts_at,'endsAt',rr.ends_at,
    'quantity',rr.quantity,'quantityUnit',rr.quantity_unit,'applyPolicyBuffers',rr.apply_policy_buffers,
    'metadata',rr.metadata||jsonb_build_object('bookingRequestId',p_request_id,'bookingRequestResourceId',rr.id),
    'provenance',rr.provenance||jsonb_build_object('bookingRequestId',p_request_id,'bookingRequestResourceId',rr.id)
  ) order by rr.starts_at,rr.id),'[]'::jsonb) into v_claims
  from ledger.booking_request_resources rr where rr.request_id=p_request_id;
  if jsonb_array_length(v_claims)=0 then raise exception 'Booking request has no Resource lines.' using errcode='23514'; end if;

  v_bundle:=ledger.establish_booking_bundle_service_v1(
    v_request.ledger_id,v_occurrence_id,v_request.booking_kind,v_claims,v_request.customer_entity_id,
    v_request.business_model_key,v_request.request_label,'confirmed',p_created_by_seat_id,
    v_request.metadata||jsonb_build_object('bookingRequestId',p_request_id,'approvedBookingRequestId',p_request_id,'requestPurpose',v_request.purpose,'commitmentEvaluation',v_commitment),
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object('bookingRequestId',p_request_id,'approvedRequestMaterialization',true),p_idempotency_key
  );

  return jsonb_build_object('contractVersion','ledger_booking_request_materialization_v2','request',ledger.booking_request_detail_v1(p_request_id),'bookingBundle',v_bundle,'commitmentEvaluation',v_commitment,'alreadyConverted',false);
end;
$$;