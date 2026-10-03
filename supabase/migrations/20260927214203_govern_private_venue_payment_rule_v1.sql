create or replace function ledger.create_booking_payment_schedule_from_policy_service_v1(
  p_request_id uuid,
  p_total_amount numeric,
  p_currency text default 'USD',
  p_agreement_id uuid default null,
  p_offer_snapshot_id uuid default null,
  p_basis_kind text default 'agreed_total',
  p_metadata jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_request ledger.booking_requests%rowtype;
  v_policy ledger.booking_policies%rowtype;
  v_threshold numeric;
  v_full_percent numeric;
  v_deposit_percent numeric;
  v_selected_percent numeric;
  v_rule text;
begin
  if p_total_amount is null or p_total_amount < 0 then
    raise exception 'Payment schedule total must be >= 0.' using errcode='22023';
  end if;
  select * into v_request from ledger.booking_requests br where br.id=p_request_id;
  if v_request.id is null then raise exception 'Booking request not found.' using errcode='P0002'; end if;

  select * into v_policy
  from ledger.booking_policies p
  where p.ledger_id=v_request.ledger_id
    and p.policy_state='active'
    and p.policy_kind='commitment'
    and (p.booking_kind is null or p.booking_kind=v_request.booking_kind)
    and coalesce((p.config->>'paymentRequiredBeforeConfirmation')::boolean,false)
  order by p.priority desc,p.stable_key,p.id
  limit 1;

  if v_policy.id is null then
    raise exception 'No active payment commitment policy governs this booking request.' using errcode='23514';
  end if;

  v_threshold:=(v_policy.config->>'fullPaymentAtOrBelowAmount')::numeric;
  v_full_percent:=(v_policy.config->>'fullPaymentPercentAtOrBelowThreshold')::numeric;
  v_deposit_percent:=(v_policy.config->>'depositPercentAboveThreshold')::numeric;

  if p_total_amount <= v_threshold then
    v_selected_percent:=v_full_percent;
    v_rule:='full_payment_at_or_below_threshold';
  else
    v_selected_percent:=v_deposit_percent;
    v_rule:='deposit_above_threshold';
  end if;

  return ledger.create_booking_payment_schedule_service_v1(
    p_request_id,p_total_amount,p_currency,v_selected_percent,true,
    p_agreement_id,p_offer_snapshot_id,p_basis_kind,
    coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object(
      'paymentPolicyId',v_policy.id,
      'paymentPolicyKey',v_policy.stable_key,
      'paymentRuleApplied',v_rule,
      'fullPaymentAtOrBelowAmount',v_threshold,
      'selectedConfirmationPercent',v_selected_percent
    ),
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object(
      'paymentPolicyId',v_policy.id,
      'paymentPolicyKey',v_policy.stable_key
    )
  );
end;
$function$;

create or replace function atlas.create_ledger_booking_payment_schedule_self_api_v1(
  p_ledger_id uuid,
  p_request_id uuid,
  p_total_amount numeric,
  p_currency text default 'USD',
  p_agreement_id uuid default null,
  p_offer_snapshot_id uuid default null,
  p_basis_kind text default 'agreed_total',
  p_metadata jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_person uuid;
  v_relation uuid;
begin
  v_relation:=atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'booking.write');
  if not exists(select 1 from ledger.booking_requests br where br.id=p_request_id and br.ledger_id=p_ledger_id) then
    raise exception 'Booking request is outside this Ledger.' using errcode='42501';
  end if;
  v_person:=atlas.current_person_id_v1();
  return ledger.create_booking_payment_schedule_from_policy_service_v1(
    p_request_id,p_total_amount,p_currency,p_agreement_id,p_offer_snapshot_id,p_basis_kind,
    coalesce(p_metadata,'{}'::jsonb),
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object(
      'performedByPersonEntityId',v_person,'responsibilityRelationId',v_relation
    )
  );
end;
$function$;

create or replace function ledger.booking_request_commitment_evaluation_v1(p_request_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_request ledger.booking_requests%rowtype;
  v_agreement_required boolean:=false;
  v_payment_required boolean:=false;
  v_threshold numeric:=null;
  v_full_percent numeric:=null;
  v_deposit_percent numeric:=null;
  v_currency text:=null;
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
    max(case when p.config ? 'fullPaymentAtOrBelowAmount' then (p.config->>'fullPaymentAtOrBelowAmount')::numeric end),
    max(case when p.config ? 'fullPaymentPercentAtOrBelowThreshold' then (p.config->>'fullPaymentPercentAtOrBelowThreshold')::numeric end),
    max(case when p.config ? 'depositPercentAboveThreshold' then (p.config->>'depositPercentAboveThreshold')::numeric end),
    max(case when p.config ? 'currency' then p.config->>'currency' end)
  into v_agreement_required,v_payment_required,v_threshold,v_full_percent,v_deposit_percent,v_currency
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
      v_unmet:=v_unmet||jsonb_build_array(jsonb_build_object(
        'reasonCode','payment_schedule_required',
        'paymentRule',jsonb_build_object(
          'fullPaymentAtOrBelowAmount',v_threshold,
          'fullPaymentPercentAtOrBelowThreshold',v_full_percent,
          'depositPercentAboveThreshold',v_deposit_percent,
          'currency',v_currency
        )
      ));
    elsif not coalesce((v_payment_position->>'confirmationPaymentsSatisfied')::boolean,false) then
      v_unmet:=v_unmet||jsonb_build_array(jsonb_build_object('reasonCode','confirmation_payment_unsatisfied','paymentPosition',v_payment_position));
    end if;
  end if;

  v_ready:=jsonb_array_length(v_unmet)=0;

  return jsonb_build_object(
    'contractVersion','ledger_booking_request_commitment_evaluation_v3',
    'requestId',v_request.id,'requestState',v_request.request_state,'bookingKind',v_request.booking_kind,
    'agreementRequired',v_agreement_required,
    'paymentRequiredBeforeConfirmation',v_payment_required,
    'paymentRule',jsonb_build_object(
      'fullPaymentAtOrBelowAmount',v_threshold,
      'fullPaymentPercentAtOrBelowThreshold',v_full_percent,
      'depositPercentAboveThreshold',v_deposit_percent,
      'currency',v_currency
    ),
    'currentAgreement',case when v_agreement.id is null then null else ledger.booking_agreement_detail_v1(v_agreement.id) end,
    'paymentPosition',v_payment_position,'activeHoldCount',v_active_holds,
    'readyForConfirmation',v_ready,'unmetRequirements',v_unmet,
    'truthBoundary',jsonb_build_object(
      'holdIsNotBooking',true,
      'approvalIsNotAgreement',true,
      'agreementIsNotPayment',true,
      'paymentAllocationRequiresSucceededCommercialPayment',true,
      'paymentScheduleMustBeDerivedFromPolicy',true
    )
  );
end;
$function$;