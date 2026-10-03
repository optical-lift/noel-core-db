create or replace function ledger.booking_payment_rule_for_total_v1(
  p_request_id uuid,
  p_total_amount numeric,
  p_currency text default 'USD'
)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_request ledger.booking_requests%rowtype;
  v_policy ledger.booking_policies%rowtype;
  v_threshold numeric;
  v_full_percent numeric;
  v_deposit_percent numeric;
  v_selected_percent numeric;
  v_confirmation_amount numeric;
  v_remaining numeric;
  v_rule text;
  v_policy_currency text;
begin
  if p_total_amount is null or p_total_amount < 0 then
    raise exception 'Payment-rule total must be >= 0.' using errcode='22023';
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
  v_policy_currency:=coalesce(v_policy.config->>'currency','USD');
  if p_currency<>v_policy_currency then
    raise exception 'Payment-rule currency % does not match governing policy currency %.',p_currency,v_policy_currency using errcode='22023';
  end if;

  if p_total_amount <= v_threshold then
    v_selected_percent:=v_full_percent;
    v_rule:='full_payment_at_or_below_threshold';
  else
    v_selected_percent:=v_deposit_percent;
    v_rule:='deposit_above_threshold';
  end if;
  v_confirmation_amount:=round((p_total_amount*v_selected_percent/100.0)::numeric,2);
  v_remaining:=round((p_total_amount-v_confirmation_amount)::numeric,2);

  return jsonb_build_object(
    'contractVersion','ledger_booking_payment_rule_v1',
    'requestId',p_request_id,
    'paymentPolicyId',v_policy.id,
    'paymentPolicyKey',v_policy.stable_key,
    'totalAmount',round(p_total_amount,2),
    'currency',v_policy_currency,
    'ruleKind',v_rule,
    'fullPaymentAtOrBelowAmount',v_threshold,
    'confirmationPercent',v_selected_percent,
    'confirmationAmount',v_confirmation_amount,
    'remainingBalance',v_remaining,
    'remainingBalanceDueTimingState',coalesce(v_policy.config->>'remainingBalanceDueTimingState','not_established'),
    'requiredForConfirmation',true
  );
end;
$function$;

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
  v_rule jsonb;
  v_percent numeric;
begin
  v_rule:=ledger.booking_payment_rule_for_total_v1(p_request_id,p_total_amount,p_currency);
  v_percent:=(v_rule->>'confirmationPercent')::numeric;
  return ledger.create_booking_payment_schedule_service_v1(
    p_request_id,p_total_amount,p_currency,v_percent,true,
    p_agreement_id,p_offer_snapshot_id,p_basis_kind,
    coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('governingPaymentRule',v_rule),
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object(
      'paymentPolicyId',v_rule->>'paymentPolicyId',
      'paymentPolicyKey',v_rule->>'paymentPolicyKey'
    )
  );
end;
$function$;