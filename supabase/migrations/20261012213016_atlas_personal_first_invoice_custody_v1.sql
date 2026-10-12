-- SOURCE-ONLY CANDIDATE: do not apply to noel-core without governed migration validation.
-- Signup collects a card; $7 service begins immediately. A same-payer editable
-- draft first-month invoice is collected within 7 days or sooner on accepted addition.
BEGIN;
CREATE TABLE atlas.personal_first_invoice_custody (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  checkout_session_id text NOT NULL UNIQUE CHECK (checkout_session_id LIKE 'cs_%'),
  stripe_customer_id text NOT NULL CHECK (stripe_customer_id LIKE 'cus_%'),
  stripe_setup_intent_id text NOT NULL CHECK (stripe_setup_intent_id LIKE 'seti_%'),
  stripe_payment_method_id text NOT NULL CHECK (stripe_payment_method_id LIKE 'pm_%'),
  stripe_subscription_id text UNIQUE CHECK (stripe_subscription_id IS NULL OR stripe_subscription_id LIKE 'sub_%'),
  stripe_invoice_id text UNIQUE CHECK (stripe_invoice_id IS NULL OR stripe_invoice_id LIKE 'in_%'),
  purchaser_email text NOT NULL CHECK (position('@' in purchaser_email)>1),
  service_started_at timestamptz NOT NULL,
  first_period_ends_at timestamptz NOT NULL,
  first_collection_due_at timestamptz NOT NULL,
  personal_first_month_cents integer NOT NULL DEFAULT 700 CHECK (personal_first_month_cents=700),
  collection_state text NOT NULL DEFAULT 'preparing' CHECK (collection_state IN ('preparing','draft','collecting','paid','failed','cancelled')),
  collection_lease_until timestamptz,
  last_stripe_event_id text,
  last_stripe_observed_at timestamptz,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(metadata)='object'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT personal_first_invoice_ready_shape CHECK (
    collection_state='preparing' OR (stripe_subscription_id IS NOT NULL AND stripe_invoice_id IS NOT NULL)
  ),
  CONSTRAINT personal_first_invoice_service_period CHECK (first_period_ends_at>service_started_at),
  CONSTRAINT personal_first_invoice_due_window CHECK (
    first_collection_due_at>=service_started_at
    AND first_collection_due_at<=service_started_at+interval '7 days'
  )
);
ALTER TABLE atlas.personal_first_invoice_custody ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.personal_first_invoice_custody FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT,UPDATE ON atlas.personal_first_invoice_custody TO service_role;


-- Only service role may register a verified Checkout Session + successful SetupIntent.
-- This freezes the enrollment clock BEFORE provider subscription/invoice creation.
CREATE OR REPLACE FUNCTION atlas.record_verified_personal_card_setup_service_v1(
 p_checkout_session_id text,p_customer_id text,p_setup_intent_id text,p_payment_method_id text,
 p_email text,p_metadata jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='pg_catalog','atlas'
AS $$
DECLARE v atlas.personal_first_invoice_custody%ROWTYPE;
        v_now timestamptz := clock_timestamp();
BEGIN
 IF p_checkout_session_id NOT LIKE 'cs_%' OR p_customer_id NOT LIKE 'cus_%'
 OR p_setup_intent_id NOT LIKE 'seti_%' OR p_payment_method_id NOT LIKE 'pm_%'
 OR position('@' in coalesce(p_email,''))<=1 OR coalesce(jsonb_typeof(p_metadata),'null')<>'object'
 THEN RAISE EXCEPTION 'Verified SetupIntent/card evidence required' USING ERRCODE='22023'; END IF;
 INSERT INTO atlas.personal_first_invoice_custody
  (checkout_session_id,stripe_customer_id,stripe_setup_intent_id,stripe_payment_method_id,
   purchaser_email,service_started_at,first_period_ends_at,first_collection_due_at,metadata)
 VALUES(p_checkout_session_id,p_customer_id,p_setup_intent_id,p_payment_method_id,
   lower(trim(p_email)),v_now,v_now+interval '1 month',v_now+interval '6 days',p_metadata)
 ON CONFLICT(checkout_session_id) DO NOTHING;
 SELECT * INTO v FROM atlas.personal_first_invoice_custody WHERE checkout_session_id=p_checkout_session_id;
 IF v.id IS NULL OR v.stripe_customer_id<>p_customer_id OR v.stripe_setup_intent_id<>p_setup_intent_id
 OR v.stripe_payment_method_id<>p_payment_method_id OR v.purchaser_email<>lower(trim(p_email))
 THEN RAISE EXCEPTION 'Card setup replay changes payer' USING ERRCODE='23505'; END IF;
 RETURN jsonb_build_object('ok',true,'custodyId',v.id,'state',v.collection_state,
   'customerId',v.stripe_customer_id,'paymentMethodId',v.stripe_payment_method_id,
   'serviceStartedAt',v.service_started_at,'firstPeriodEndsAt',v.first_period_ends_at,
   'firstCollectionDueAt',v.first_collection_due_at,'subscriptionId',v.stripe_subscription_id,
   'invoiceId',v.stripe_invoice_id);
END $$;

CREATE OR REPLACE FUNCTION atlas.record_personal_first_invoice_service_v1(
  p_checkout_session_id text,p_customer_id text,p_subscription_id text,p_invoice_id text,
  p_email text,p_service_started_at timestamptz,p_first_period_ends_at timestamptz,
  p_due_at timestamptz,p_metadata jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path='pg_catalog','atlas'
AS $$
DECLARE v atlas.personal_first_invoice_custody%ROWTYPE;
BEGIN
  IF p_checkout_session_id NOT LIKE 'cs_%' OR p_customer_id NOT LIKE 'cus_%'
    OR p_subscription_id NOT LIKE 'sub_%' OR p_invoice_id NOT LIKE 'in_%'
    OR nullif(lower(trim(p_email)),'') IS NULL OR position('@' in p_email)<=1
    OR p_service_started_at IS NULL OR p_first_period_ends_at IS NULL OR p_due_at IS NULL
    OR p_due_at<p_service_started_at OR p_due_at>p_service_started_at+interval '7 days'
    OR p_first_period_ends_at<=p_service_started_at
    OR coalesce(jsonb_typeof(p_metadata),'null')<>'object'
  THEN RAISE EXCEPTION 'Invalid first-month invoice custody evidence' USING ERRCODE='22023'; END IF;
  -- Server setup stage must exist first; never infer enrollment time from an unchecked callback.
  SELECT * INTO v FROM atlas.personal_first_invoice_custody
  WHERE checkout_session_id=p_checkout_session_id FOR UPDATE;
  IF v.id IS NULL OR v.stripe_customer_id<>p_customer_id
    OR v.purchaser_email<>lower(trim(p_email))
    OR v.service_started_at<>p_service_started_at
    OR v.first_period_ends_at<>p_first_period_ends_at
    OR v.first_collection_due_at<>p_due_at
    OR (v.stripe_subscription_id IS NOT NULL AND v.stripe_subscription_id<>p_subscription_id)
    OR (v.stripe_invoice_id IS NOT NULL AND v.stripe_invoice_id<>p_invoice_id)
  THEN RAISE EXCEPTION 'First-month invoice replay changes immutable custody' USING ERRCODE='23505'; END IF;
  IF v.collection_state='preparing' THEN
    UPDATE atlas.personal_first_invoice_custody
    SET stripe_subscription_id=p_subscription_id,stripe_invoice_id=p_invoice_id,
        collection_state='draft',metadata=metadata||p_metadata,updated_at=now()
    WHERE id=v.id RETURNING * INTO v;
  END IF;
  RETURN jsonb_build_object('ok',true,'custodyId',v.id,'state',v.collection_state,'invoiceId',v.stripe_invoice_id);
END $$;

CREATE OR REPLACE FUNCTION atlas.read_personal_first_invoice_service_v1(p_checkout_session_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='pg_catalog','atlas'
AS $$
DECLARE v atlas.personal_first_invoice_custody%ROWTYPE;
BEGIN
 IF p_checkout_session_id NOT LIKE 'cs_%' THEN RAISE EXCEPTION 'Session required' USING ERRCODE='22023'; END IF;
 SELECT * INTO v FROM atlas.personal_first_invoice_custody WHERE checkout_session_id=p_checkout_session_id;
 IF v.id IS NULL THEN RETURN jsonb_build_object('found',false); END IF;
 RETURN jsonb_build_object('found',true,'state',v.collection_state,'customerId',v.stripe_customer_id,
  'subscriptionId',v.stripe_subscription_id,'invoiceId',v.stripe_invoice_id,
  'serviceStartedAt',v.service_started_at,'firstPeriodEndsAt',v.first_period_ends_at,
  'firstCollectionDueAt',v.first_collection_due_at,
  'purchaserEmail',v.purchaser_email,'paymentMethodId',v.stripe_payment_method_id);
END $$;

CREATE OR REPLACE FUNCTION atlas.claim_due_personal_first_invoices_service_v1(p_limit integer DEFAULT 25)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path='pg_catalog','atlas'
AS $$
DECLARE v_items jsonb;
BEGIN
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'Invalid invoice claim limit' USING ERRCODE='22023';
  END IF;
  WITH targets AS (
    SELECT id FROM atlas.personal_first_invoice_custody
    WHERE first_collection_due_at<=now()
      AND (collection_state='draft'
        OR (collection_state='collecting' AND collection_lease_until<now()))
    ORDER BY first_collection_due_at,id
    FOR UPDATE SKIP LOCKED LIMIT p_limit
  ), reserved AS (
    UPDATE atlas.personal_first_invoice_custody x
    SET collection_state='collecting',collection_lease_until=now()+interval '15 minutes',updated_at=now()
    FROM targets t WHERE x.id=t.id
    RETURNING x.id,x.checkout_session_id,x.stripe_customer_id,x.stripe_invoice_id,
              x.first_collection_due_at,x.personal_first_month_cents
  ) SELECT coalesce(jsonb_agg(to_jsonb(reserved)),'[]'::jsonb) INTO v_items FROM reserved;
  RETURN jsonb_build_object('items',v_items);
END $$;

CREATE OR REPLACE FUNCTION atlas.record_personal_first_invoice_result_service_v1(
  p_invoice_id text,p_status text,p_stripe_event_id text,p_observed_at timestamptz
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path='pg_catalog','atlas'
AS $$
DECLARE v atlas.personal_first_invoice_custody%ROWTYPE;
BEGIN
  IF p_invoice_id NOT LIKE 'in_%' OR p_status NOT IN ('paid','failed','cancelled')
    OR nullif(trim(p_stripe_event_id),'') IS NULL OR p_observed_at IS NULL
  THEN RAISE EXCEPTION 'Invalid invoice settlement receipt' USING ERRCODE='22023'; END IF;
  SELECT * INTO v FROM atlas.personal_first_invoice_custody
    WHERE stripe_invoice_id=p_invoice_id FOR UPDATE;
  IF v.id IS NULL THEN RAISE EXCEPTION 'Unknown invoice' USING ERRCODE='P0002'; END IF;
  IF v.collection_state='paid' AND p_status<>'paid'
    THEN RAISE EXCEPTION 'A settled invoice cannot be reopened by event replay' USING ERRCODE='23514'; END IF;
  IF v.last_stripe_observed_at IS NOT NULL AND p_observed_at<v.last_stripe_observed_at
    THEN RETURN jsonb_build_object('ok',true,'staleEventIgnored',true,'state',v.collection_state); END IF;
  UPDATE atlas.personal_first_invoice_custody
    SET collection_state=p_status,collection_lease_until=NULL,
      last_stripe_event_id=p_stripe_event_id,last_stripe_observed_at=p_observed_at,updated_at=now()
    WHERE id=v.id;
  RETURN jsonb_build_object('ok',true,'state',p_status,'custodyId',v.id);
END $$;

-- Reconcile provider subscription status AND the independently owed first invoice.
-- Later subscription webhooks cannot accidentally reactivate a failed first-month invoice.
CREATE OR REPLACE FUNCTION atlas.reconcile_personal_first_invoice_access_service_v1(
  p_subscription_id text,p_current_stripe_status text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path='pg_catalog','atlas'
AS $$
DECLARE v atlas.personal_first_invoice_custody%ROWTYPE;
        v_subscription_state text;
        v_state text;
        v_rows integer;
BEGIN
 IF p_subscription_id NOT LIKE 'sub_%' OR nullif(trim(p_current_stripe_status),'') IS NULL
 THEN RAISE EXCEPTION 'Verified subscription status required' USING ERRCODE='22023'; END IF;
 SELECT * INTO v FROM atlas.personal_first_invoice_custody
 WHERE stripe_subscription_id=p_subscription_id FOR UPDATE;
 IF v.id IS NULL THEN RETURN jsonb_build_object('ok',true,'matched',false); END IF;
 v_subscription_state:=atlas.personal_atlas_purchase_state_from_stripe_status_internal_v1(p_current_stripe_status);
 v_state:=CASE
  WHEN v.collection_state='failed' THEN 'past_due'
  WHEN v.collection_state='cancelled' THEN 'cancelled'
  ELSE v_subscription_state END;
 UPDATE atlas.personal_atlas_purchases p SET
   purchase_state=v_state,
   metadata=p.metadata||jsonb_build_object('firstMonthInvoiceState',v.collection_state,
      'latestCurrentStripeSubscriptionStatus',p_current_stripe_status),
   updated_at=now()
 WHERE p.provider='stripe' AND p.provider_checkout_session_id=v.checkout_session_id
   AND p.provider_subscription_id=p_subscription_id
   AND p.metadata->>'firstMonthInvoiceId'=v.stripe_invoice_id;
 GET DIAGNOSTICS v_rows=ROW_COUNT;
 RETURN jsonb_build_object('ok',true,'matched',v_rows>0,'state',v_state,
   'firstMonthInvoiceState',v.collection_state);
END $$;

REVOKE ALL ON FUNCTION atlas.reconcile_personal_first_invoice_access_service_v1(text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION atlas.reconcile_personal_first_invoice_access_service_v1(text,text) TO service_role;
REVOKE ALL ON FUNCTION atlas.record_verified_personal_card_setup_service_v1(text,text,text,text,text,jsonb) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.read_personal_first_invoice_service_v1(text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.record_personal_first_invoice_service_v1(text,text,text,text,text,timestamptz,timestamptz,timestamptz,jsonb) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.claim_due_personal_first_invoices_service_v1(integer) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.record_personal_first_invoice_result_service_v1(text,text,text,timestamptz) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION atlas.record_verified_personal_card_setup_service_v1(text,text,text,text,text,jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION atlas.read_personal_first_invoice_service_v1(text) TO service_role;
GRANT EXECUTE ON FUNCTION atlas.record_personal_first_invoice_service_v1(text,text,text,text,text,timestamptz,timestamptz,timestamptz,jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION atlas.claim_due_personal_first_invoices_service_v1(integer) TO service_role;
GRANT EXECUTE ON FUNCTION atlas.record_personal_first_invoice_result_service_v1(text,text,text,timestamptz) TO service_role;
-- Required PostgREST public gateways for trusted server-only Stripe billing RPCs.
-- service_role alone may call them; public/anon/authenticated may not.
CREATE OR REPLACE FUNCTION public.record_verified_personal_card_setup_service_v1(p_checkout_session_id text, p_customer_id text, p_setup_intent_id text, p_payment_method_id text, p_email text, p_metadata jsonb)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER
SET search_path='pg_catalog'
AS $$ SELECT atlas.record_verified_personal_card_setup_service_v1($1,$2,$3,$4,$5,$6); $$;
REVOKE ALL ON FUNCTION public.record_verified_personal_card_setup_service_v1(text,text,text,text,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.record_verified_personal_card_setup_service_v1(text,text,text,text,text,jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public.record_personal_first_invoice_service_v1(p_checkout_session_id text, p_customer_id text, p_subscription_id text, p_invoice_id text, p_email text, p_service_started_at timestamptz, p_first_period_ends_at timestamptz, p_due_at timestamptz, p_metadata jsonb)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER
SET search_path='pg_catalog'
AS $$ SELECT atlas.record_personal_first_invoice_service_v1($1,$2,$3,$4,$5,$6,$7,$8,$9); $$;
REVOKE ALL ON FUNCTION public.record_personal_first_invoice_service_v1(text,text,text,text,text,timestamptz,timestamptz,timestamptz,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.record_personal_first_invoice_service_v1(text,text,text,text,text,timestamptz,timestamptz,timestamptz,jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public.read_personal_first_invoice_service_v1(p_checkout_session_id text)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER
SET search_path='pg_catalog'
AS $$ SELECT atlas.read_personal_first_invoice_service_v1($1); $$;
REVOKE ALL ON FUNCTION public.read_personal_first_invoice_service_v1(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_personal_first_invoice_service_v1(text) TO service_role;

CREATE OR REPLACE FUNCTION public.claim_due_personal_first_invoices_service_v1(p_limit integer)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER
SET search_path='pg_catalog'
AS $$ SELECT atlas.claim_due_personal_first_invoices_service_v1($1); $$;
REVOKE ALL ON FUNCTION public.claim_due_personal_first_invoices_service_v1(integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_due_personal_first_invoices_service_v1(integer) TO service_role;

CREATE OR REPLACE FUNCTION public.record_personal_first_invoice_result_service_v1(p_invoice_id text, p_status text, p_stripe_event_id text, p_observed_at timestamptz)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER
SET search_path='pg_catalog'
AS $$ SELECT atlas.record_personal_first_invoice_result_service_v1($1,$2,$3,$4); $$;
REVOKE ALL ON FUNCTION public.record_personal_first_invoice_result_service_v1(text,text,text,timestamptz) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.record_personal_first_invoice_result_service_v1(text,text,text,timestamptz) TO service_role;

CREATE OR REPLACE FUNCTION public.reconcile_personal_first_invoice_access_service_v1(p_subscription_id text, p_current_stripe_status text)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER
SET search_path='pg_catalog'
AS $$ SELECT atlas.reconcile_personal_first_invoice_access_service_v1($1,$2); $$;
REVOKE ALL ON FUNCTION public.reconcile_personal_first_invoice_access_service_v1(text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_personal_first_invoice_access_service_v1(text,text) TO service_role;

CREATE OR REPLACE FUNCTION public.record_stripe_personal_atlas_purchase_v2(p_checkout_session_id text, p_subscription_id text, p_purchaser_email text, p_purchased_at timestamptz, p_current_stripe_status text, p_metadata jsonb)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER
SET search_path='pg_catalog'
AS $$ SELECT atlas.record_stripe_personal_atlas_purchase_v2($1,$2,$3,$4,$5,$6); $$;
REVOKE ALL ON FUNCTION public.record_stripe_personal_atlas_purchase_v2(text,text,text,timestamptz,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.record_stripe_personal_atlas_purchase_v2(text,text,text,timestamptz,text,jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public.record_stripe_personal_atlas_subscription_state_v2(p_subscription_id text, p_event_type text, p_event_status text, p_event_id text, p_event_created_at timestamptz, p_current_stripe_status text)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER
SET search_path='pg_catalog'
AS $$ SELECT atlas.record_stripe_personal_atlas_subscription_state_v2($1,$2,$3,$4,$5,$6); $$;
REVOKE ALL ON FUNCTION public.record_stripe_personal_atlas_subscription_state_v2(text,text,text,text,timestamptz,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.record_stripe_personal_atlas_subscription_state_v2(text,text,text,text,timestamptz,text) TO service_role;

COMMIT;
