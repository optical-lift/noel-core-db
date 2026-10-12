-- SOURCE-ONLY CANDIDATE: do not apply to noel-core without governed migration validation.
-- Signup collects a card; $7 service begins immediately. A same-payer editable
-- draft first-month invoice is collected within 7 days or sooner on accepted addition.
BEGIN;
CREATE TABLE atlas.personal_first_invoice_custody (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  checkout_session_id text NOT NULL UNIQUE CHECK (checkout_session_id LIKE 'cs_%'),
  stripe_customer_id text NOT NULL CHECK (stripe_customer_id LIKE 'cus_%'),
  stripe_subscription_id text NOT NULL CHECK (stripe_subscription_id LIKE 'sub_%'),
  stripe_invoice_id text NOT NULL UNIQUE CHECK (stripe_invoice_id LIKE 'in_%'),
  purchaser_email text NOT NULL CHECK (position('@' in purchaser_email)>1),
  service_started_at timestamptz NOT NULL,
  first_period_ends_at timestamptz NOT NULL,
  first_collection_due_at timestamptz NOT NULL,
  personal_first_month_cents integer NOT NULL DEFAULT 700 CHECK (personal_first_month_cents=700),
  collection_state text NOT NULL DEFAULT 'draft' CHECK (collection_state IN ('draft','collecting','paid','failed','cancelled')),
  collection_lease_until timestamptz,
  last_stripe_event_id text,
  last_stripe_observed_at timestamptz,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(metadata)='object'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT personal_first_invoice_service_period CHECK (first_period_ends_at>service_started_at),
  CONSTRAINT personal_first_invoice_due_window CHECK (
    first_collection_due_at>=service_started_at
    AND first_collection_due_at<=service_started_at+interval '7 days'
  )
);
ALTER TABLE atlas.personal_first_invoice_custody ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.personal_first_invoice_custody FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT,UPDATE ON atlas.personal_first_invoice_custody TO service_role;

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
  INSERT INTO atlas.personal_first_invoice_custody(
    checkout_session_id,stripe_customer_id,stripe_subscription_id,stripe_invoice_id,purchaser_email,
    service_started_at,first_period_ends_at,first_collection_due_at,metadata
  ) VALUES (
    p_checkout_session_id,p_customer_id,p_subscription_id,p_invoice_id,lower(trim(p_email)),
    p_service_started_at,p_first_period_ends_at,p_due_at,p_metadata
  ) ON CONFLICT (checkout_session_id) DO NOTHING;
  SELECT * INTO v FROM atlas.personal_first_invoice_custody WHERE checkout_session_id=p_checkout_session_id;
  IF v.id IS NULL OR v.stripe_customer_id<>p_customer_id
    OR v.stripe_subscription_id<>p_subscription_id
    OR v.stripe_invoice_id<>p_invoice_id
    OR v.purchaser_email<>lower(trim(p_email))
    OR v.service_started_at<>p_service_started_at OR v.first_period_ends_at<>p_first_period_ends_at
    OR v.first_collection_due_at<>p_due_at
  THEN RAISE EXCEPTION 'First-month invoice replay changes provider custody' USING ERRCODE='23505'; END IF;
  RETURN jsonb_build_object('ok',true,'custodyId',v.id,'state',v.collection_state,'invoiceId',v.stripe_invoice_id);
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
REVOKE ALL ON FUNCTION atlas.record_personal_first_invoice_service_v1(text,text,text,text,text,timestamptz,timestamptz,timestamptz,jsonb) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.claim_due_personal_first_invoices_service_v1(integer) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.record_personal_first_invoice_result_service_v1(text,text,text,timestamptz) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION atlas.record_personal_first_invoice_service_v1(text,text,text,text,text,timestamptz,timestamptz,timestamptz,jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION atlas.claim_due_personal_first_invoices_service_v1(integer) TO service_role;
GRANT EXECUTE ON FUNCTION atlas.record_personal_first_invoice_result_service_v1(text,text,text,timestamptz) TO service_role;
COMMIT;
