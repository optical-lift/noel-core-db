-- UNRELEASED CANDIDATE. Requires disposable-clone testing and governed migration generator.
-- Supersedes upfront $3,000 Ledger onboarding price; preserves historical records.
BEGIN;
ALTER TABLE atlas.implementation_purchases
  ALTER COLUMN setup_contract_amount_cents DROP NOT NULL;
ALTER TABLE atlas.ledger_entitlements
  ALTER COLUMN setup_price_cents DROP NOT NULL;

ALTER TABLE atlas.implementation_purchases DROP CONSTRAINT implementation_purchases_payment_option_check;
ALTER TABLE atlas.implementation_purchases ADD CONSTRAINT implementation_purchases_payment_option_check
  CHECK (payment_option IN ('pay_in_full','three_installments','foundry_assessed'));
ALTER TABLE atlas.implementation_purchases ADD CONSTRAINT implementation_purchases_foundry_pending_shape
  CHECK (payment_option <> 'foundry_assessed' OR setup_contract_amount_cents IS NULL);

-- New v2 writer only. v1 historical paid-checkout idempotency remains available.
CREATE OR REPLACE FUNCTION atlas.record_stripe_implementation_purchase_v2(p_checkout_session_id text, p_subscription_id text, p_offer_key text, p_starting_label text, p_payment_option text, p_setup_contract_amount_cents integer, p_monthly_ledger_unit_price_cents integer, p_recurring_starts_at timestamp with time zone, p_purchased_at timestamp with time zone DEFAULT now(), p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_purchase atlas.implementation_purchases%rowtype;
  v_case atlas.implementation_cases%rowtype;
  v_entitlement atlas.ledger_entitlements%rowtype;
  v_label text := btrim(coalesce(p_starting_label,''));
begin
  if btrim(coalesce(p_checkout_session_id,'')) = '' or p_checkout_session_id !~ '^cs_' then
    raise exception 'Valid Stripe Checkout Session id required.' using errcode='22023';
  end if;
  if btrim(coalesce(p_offer_key,'')) = '' then
    raise exception 'Offer key required.' using errcode='22023';
  end if;
  if length(v_label) < 1 or length(v_label) > 160 then
    raise exception 'Starting label must be between 1 and 160 characters.' using errcode='22023';
  end if;
  if p_payment_option is distinct from 'foundry_assessed' then
    raise exception 'Only Foundry-assessed onboarding is accepted by v2.' using errcode='22023';
  end if;
  if p_setup_contract_amount_cents is not null then
    raise exception 'No onboarding contract price may be asserted before Foundry decision.' using errcode='22023';
  end if;
  if p_monthly_ledger_unit_price_cents is null or p_monthly_ledger_unit_price_cents < 0 then
    raise exception 'Monthly Ledger subscription must be non-negative.' using errcode='22023';
  end if;
  if p_metadata is null or jsonb_typeof(p_metadata) <> 'object' then
    raise exception 'Purchase metadata must be a JSON object.' using errcode='22023';
  end if;

  insert into atlas.implementation_purchases (
    provider, provider_checkout_session_id, provider_subscription_id, offer_key,
    starting_label, payment_option, purchase_state, currency,
    setup_contract_amount_cents, monthly_ledger_unit_price_cents,
    recurring_starts_at, purchased_at, metadata
  ) values (
    'stripe', p_checkout_session_id, nullif(btrim(coalesce(p_subscription_id,'')),''), btrim(p_offer_key),
    v_label, p_payment_option, 'active', 'usd',
    p_setup_contract_amount_cents, p_monthly_ledger_unit_price_cents,
    p_recurring_starts_at, coalesce(p_purchased_at,now()), p_metadata
  )
  on conflict (provider, provider_checkout_session_id) do nothing
  returning * into v_purchase;

  if v_purchase.id is null then
    select * into strict v_purchase
    from atlas.implementation_purchases
    where provider='stripe' and provider_checkout_session_id=p_checkout_session_id;

    if v_purchase.provider_subscription_id is distinct from nullif(btrim(coalesce(p_subscription_id,'')),'')
       or v_purchase.offer_key is distinct from btrim(p_offer_key)
       or v_purchase.starting_label is distinct from v_label
       or v_purchase.payment_option is distinct from p_payment_option
       or v_purchase.setup_contract_amount_cents is distinct from p_setup_contract_amount_cents
       or v_purchase.monthly_ledger_unit_price_cents is distinct from p_monthly_ledger_unit_price_cents
       or v_purchase.recurring_starts_at is distinct from p_recurring_starts_at then
      raise exception 'Existing Stripe implementation purchase does not match supplied commercial evidence.' using errcode='23505';
    end if;
  end if;

  insert into atlas.implementation_cases (implementation_purchase_id, state, metadata)
  values (
    v_purchase.id,
    'awaiting_setup_human',
    jsonb_build_object('source','record_stripe_implementation_purchase_v1')
  )
  on conflict (implementation_purchase_id) do nothing
  returning * into v_case;

  if v_case.id is null then
    select * into strict v_case
    from atlas.implementation_cases
    where implementation_purchase_id=v_purchase.id;
  end if;

  insert into atlas.ledger_entitlements (
    implementation_case_id, source_purchase_id, entitlement_number, entitlement_kind,
    price_class, state, setup_price_cents, monthly_price_cents,
    recurring_starts_at, purchased_at, commercial_basis
  ) values (
    v_case.id, v_purchase.id, 1, 'atlas_ledger',
    'baseline_first', 'available', p_setup_contract_amount_cents, p_monthly_ledger_unit_price_cents,
    p_recurring_starts_at, v_purchase.purchased_at,
    jsonb_build_object(
      'provider','stripe',
      'checkoutSessionId',p_checkout_session_id,
      'purchaseId',v_purchase.id,
      'meaning','One baseline Ledger entitlement; no institutional scope established yet.',
      'onboardingAssessmentState','pending_foundry_assessment',
      'quotedSetupAmountKnown',false
    )
  )
  on conflict (implementation_case_id, entitlement_number) do nothing
  returning * into v_entitlement;

  if v_entitlement.id is null then
    select * into strict v_entitlement
    from atlas.ledger_entitlements
    where implementation_case_id=v_case.id and entitlement_number=1;

    if v_entitlement.source_purchase_id is distinct from v_purchase.id
       or v_entitlement.setup_price_cents is distinct from p_setup_contract_amount_cents
       or v_entitlement.monthly_price_cents is distinct from p_monthly_ledger_unit_price_cents then
      raise exception 'Existing baseline Ledger entitlement does not match purchase evidence.' using errcode='23505';
    end if;
  end if;

  return jsonb_build_object(
    'purchaseId',v_purchase.id,
    'implementationCaseId',v_case.id,
    'caseState',v_case.state,
    'ledgerEntitlementId',v_entitlement.id,
    'ledgerEntitlementState',v_entitlement.state,
    'institutionCreated',false,
    'membershipCreated',false,
    'principalCreated',false
  );
end;
$function$;

REVOKE ALL ON FUNCTION atlas.record_stripe_implementation_purchase_v2(
  text,text,text,text,text,integer,integer,timestamptz,timestamptz,jsonb
) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION atlas.record_stripe_implementation_purchase_v2(
  text,text,text,text,text,integer,integer,timestamptz,timestamptz,jsonb
) TO service_role;
COMMIT;
