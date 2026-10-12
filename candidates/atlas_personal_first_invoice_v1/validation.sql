-- Clone-only validation. ALL fixture writes rolled back.
BEGIN;
DO $validation$
DECLARE
 v jsonb;
 v_again jsonb;
 v_bill jsonb;
 v_reconcile jsonb;
 v_due jsonb;
 v_id uuid;
 v_start timestamptz;
 v_end timestamptz;
 v_due_at timestamptz;
 v_stat text;
BEGIN
 IF to_regclass('atlas.personal_first_invoice_custody') IS NULL
    OR to_regprocedure('atlas.record_verified_personal_card_setup_service_v1(text,text,text,text,text,jsonb)') IS NULL
    OR to_regprocedure('atlas.read_personal_first_invoice_service_v1(text)') IS NULL
    OR to_regprocedure('atlas.record_personal_first_invoice_service_v1(text,text,text,text,text,timestamptz,timestamptz,timestamptz,jsonb)') IS NULL
    OR to_regprocedure('atlas.reconcile_personal_first_invoice_access_service_v1(text,text)') IS NULL
 THEN RAISE EXCEPTION 'First-month SQL candidate was not applied in the disposable clone'; END IF;
 IF has_table_privilege('authenticated','atlas.personal_first_invoice_custody','SELECT')
    OR has_table_privilege('anon','atlas.personal_first_invoice_custody','SELECT')
    OR has_function_privilege('anon','atlas.record_verified_personal_card_setup_service_v1(text,text,text,text,text,jsonb)','EXECUTE')
    OR has_function_privilege('authenticated','atlas.read_personal_first_invoice_service_v1(text)','EXECUTE')
    OR NOT has_function_privilege('service_role','atlas.record_verified_personal_card_setup_service_v1(text,text,text,text,text,jsonb)','EXECUTE')
 THEN RAISE EXCEPTION 'Invoice custody ACL failed'; END IF;
 v:=atlas.record_verified_personal_card_setup_service_v1(
    'cs_fixture_atlas_oct_2026','cus_fixture_atlas_oct','seti_fixture_atlas_oct','pm_fixture_atlas_oct',
    'Foundry@example.invalid','{"fixture":true}'::jsonb);
 IF v->>'state'<>'preparing' OR v->>'invoiceId' IS NOT NULL
 THEN RAISE EXCEPTION 'Initial card custody stage incorrect: %',v; END IF;
 v_id:=(v->>'custodyId')::uuid;
 v_start:=(v->>'serviceStartedAt')::timestamptz;
 v_end:=(v->>'firstPeriodEndsAt')::timestamptz;
 v_due_at:=(v->>'firstCollectionDueAt')::timestamptz;
 IF v_due_at<>v_start+interval '6 days' OR v_end<>(v_start+interval '1 month')
 THEN RAISE EXCEPTION 'Enrollment clock and daily collector threshold inconsistent'; END IF;
 v_again:=atlas.record_verified_personal_card_setup_service_v1(
    'cs_fixture_atlas_oct_2026','cus_fixture_atlas_oct','seti_fixture_atlas_oct','pm_fixture_atlas_oct',
    'foundry@example.invalid','{"fixture":"replay"}'::jsonb);
 IF v_again->>'custodyId'<>v->>'custodyId' OR v_again->>'serviceStartedAt'<>v->>'serviceStartedAt'
 THEN RAISE EXCEPTION 'Card setup replay changed original claim'; END IF;
 BEGIN
   PERFORM atlas.record_verified_personal_card_setup_service_v1(
      'cs_fixture_atlas_oct_2026','cus_wrong','seti_fixture_atlas_oct','pm_fixture_atlas_oct',
      'foundry@example.invalid','{}'::jsonb);
   RAISE EXCEPTION 'Changed payer was silently accepted';
 EXCEPTION WHEN unique_violation THEN NULL;
 END;
 v_bill:=atlas.record_personal_first_invoice_service_v1(
   'cs_fixture_atlas_oct_2026','cus_fixture_atlas_oct','sub_fixture_atlas_oct','in_fixture_atlas_oct',
   'foundry@example.invalid',v_start,v_end,v_due_at,'{"fixture":true}'::jsonb);
 IF v_bill->>'state'<>'draft' OR v_bill->>'invoiceId'<>'in_fixture_atlas_oct'
 THEN RAISE EXCEPTION 'Original $7 draft invoice was not bound: %',v_bill; END IF;
 v_again:=atlas.record_personal_first_invoice_service_v1(
   'cs_fixture_atlas_oct_2026','cus_fixture_atlas_oct','sub_fixture_atlas_oct','in_fixture_atlas_oct',
   'foundry@example.invalid',v_start,v_end,v_due_at,'{}'::jsonb);
 IF v_again->>'custodyId'<>v_bill->>'custodyId'
 THEN RAISE EXCEPTION 'Same-invoice replay changed custody'; END IF;
 BEGIN
   PERFORM atlas.record_personal_first_invoice_service_v1(
     'cs_fixture_atlas_oct_2026','cus_fixture_atlas_oct','sub_fixture_atlas_oct','in_second_invoice',
     'foundry@example.invalid',v_start,v_end,v_due_at,'{}'::jsonb);
   RAISE EXCEPTION 'Different first invoice was permitted';
 EXCEPTION WHEN unique_violation THEN NULL;
 END;
 INSERT INTO atlas.personal_atlas_purchases(
    provider,provider_checkout_session_id,provider_subscription_id,purchaser_email,
    offer_key,purchase_state,purchased_at,metadata
 ) VALUES(
    'stripe','cs_fixture_atlas_oct_2026','sub_fixture_atlas_oct','foundry@example.invalid',
    'personal_atlas','active',v_start,
    '{"firstMonthInvoiceId":"in_fixture_atlas_oct","firstMonthInvoiced":true}'::jsonb
 );
 v_reconcile:=atlas.reconcile_personal_first_invoice_access_service_v1(
   'sub_fixture_atlas_oct','trialing');
 IF v_reconcile->>'state'<>'active'
 THEN RAISE EXCEPTION 'Pending authorized first-month invoice did not allow initial service'; END IF;
 v:=atlas.record_personal_first_invoice_result_service_v1(
    'in_fixture_atlas_oct','failed','evt_failed_oct',now());
 IF v->>'state'<>'failed' THEN RAISE EXCEPTION 'Failed receipt not recorded'; END IF;
 v_reconcile:=atlas.reconcile_personal_first_invoice_access_service_v1(
   'sub_fixture_atlas_oct','trialing');
 IF v_reconcile->>'state'<>'past_due' THEN RAISE EXCEPTION 'Trialing subscription bypassed unpaid invoice'; END IF;
 SELECT purchase_state INTO v_stat FROM atlas.personal_atlas_purchases
 WHERE provider_checkout_session_id='cs_fixture_atlas_oct_2026';
 IF v_stat<>'past_due' THEN RAISE EXCEPTION 'Purchase remained active despite failed first invoice'; END IF;
 v:=atlas.record_personal_first_invoice_result_service_v1(
    'in_fixture_atlas_oct','paid','evt_paid_oct',now()+interval '1 minute');
 v_reconcile:=atlas.reconcile_personal_first_invoice_access_service_v1(
   'sub_fixture_atlas_oct','trialing');
 IF v->>'state'<>'paid' OR v_reconcile->>'state'<>'active'
 THEN RAISE EXCEPTION 'Verified paid invoice did not restore active access'; END IF;
 BEGIN
   PERFORM atlas.record_personal_first_invoice_result_service_v1(
     'in_fixture_atlas_oct','failed','evt_stale_failed',now()+interval '2 minutes');
   RAISE EXCEPTION 'Paid invoice reopened';
 EXCEPTION WHEN check_violation THEN NULL;
 END;
 v_due:=atlas.claim_due_personal_first_invoices_service_v1(25);
 IF coalesce(jsonb_array_length(v_due->'items'),0)<>0
 THEN RAISE EXCEPTION 'Paid invoice was incorrectly claimed for collection'; END IF;
  IF to_regprocedure('public.record_verified_personal_card_setup_service_v1(text,text,text,text,text,jsonb)') IS NULL
 OR has_function_privilege('anon','public.record_verified_personal_card_setup_service_v1(text,text,text,text,text,jsonb)','EXECUTE')
 OR has_function_privilege('authenticated','public.record_verified_personal_card_setup_service_v1(text,text,text,text,text,jsonb)','EXECUTE')
 OR NOT has_function_privilege('service_role','public.record_verified_personal_card_setup_service_v1(text,text,text,text,text,jsonb)','EXECUTE')
 THEN RAISE EXCEPTION 'Billing public gateway ACL absent or exposed: record_verified_personal_card_setup_service_v1'; END IF;
  IF to_regprocedure('public.record_personal_first_invoice_service_v1(text,text,text,text,text,timestamptz,timestamptz,timestamptz,jsonb)') IS NULL
 OR has_function_privilege('anon','public.record_personal_first_invoice_service_v1(text,text,text,text,text,timestamptz,timestamptz,timestamptz,jsonb)','EXECUTE')
 OR has_function_privilege('authenticated','public.record_personal_first_invoice_service_v1(text,text,text,text,text,timestamptz,timestamptz,timestamptz,jsonb)','EXECUTE')
 OR NOT has_function_privilege('service_role','public.record_personal_first_invoice_service_v1(text,text,text,text,text,timestamptz,timestamptz,timestamptz,jsonb)','EXECUTE')
 THEN RAISE EXCEPTION 'Billing public gateway ACL absent or exposed: record_personal_first_invoice_service_v1'; END IF;
  IF to_regprocedure('public.read_personal_first_invoice_service_v1(text)') IS NULL
 OR has_function_privilege('anon','public.read_personal_first_invoice_service_v1(text)','EXECUTE')
 OR has_function_privilege('authenticated','public.read_personal_first_invoice_service_v1(text)','EXECUTE')
 OR NOT has_function_privilege('service_role','public.read_personal_first_invoice_service_v1(text)','EXECUTE')
 THEN RAISE EXCEPTION 'Billing public gateway ACL absent or exposed: read_personal_first_invoice_service_v1'; END IF;
  IF to_regprocedure('public.claim_due_personal_first_invoices_service_v1(integer)') IS NULL
 OR has_function_privilege('anon','public.claim_due_personal_first_invoices_service_v1(integer)','EXECUTE')
 OR has_function_privilege('authenticated','public.claim_due_personal_first_invoices_service_v1(integer)','EXECUTE')
 OR NOT has_function_privilege('service_role','public.claim_due_personal_first_invoices_service_v1(integer)','EXECUTE')
 THEN RAISE EXCEPTION 'Billing public gateway ACL absent or exposed: claim_due_personal_first_invoices_service_v1'; END IF;
  IF to_regprocedure('public.record_personal_first_invoice_result_service_v1(text,text,text,timestamptz)') IS NULL
 OR has_function_privilege('anon','public.record_personal_first_invoice_result_service_v1(text,text,text,timestamptz)','EXECUTE')
 OR has_function_privilege('authenticated','public.record_personal_first_invoice_result_service_v1(text,text,text,timestamptz)','EXECUTE')
 OR NOT has_function_privilege('service_role','public.record_personal_first_invoice_result_service_v1(text,text,text,timestamptz)','EXECUTE')
 THEN RAISE EXCEPTION 'Billing public gateway ACL absent or exposed: record_personal_first_invoice_result_service_v1'; END IF;
  IF to_regprocedure('public.reconcile_personal_first_invoice_access_service_v1(text,text)') IS NULL
 OR has_function_privilege('anon','public.reconcile_personal_first_invoice_access_service_v1(text,text)','EXECUTE')
 OR has_function_privilege('authenticated','public.reconcile_personal_first_invoice_access_service_v1(text,text)','EXECUTE')
 OR NOT has_function_privilege('service_role','public.reconcile_personal_first_invoice_access_service_v1(text,text)','EXECUTE')
 THEN RAISE EXCEPTION 'Billing public gateway ACL absent or exposed: reconcile_personal_first_invoice_access_service_v1'; END IF;
  IF to_regprocedure('public.record_stripe_personal_atlas_purchase_v2(text,text,text,timestamptz,text,jsonb)') IS NULL
 OR has_function_privilege('anon','public.record_stripe_personal_atlas_purchase_v2(text,text,text,timestamptz,text,jsonb)','EXECUTE')
 OR has_function_privilege('authenticated','public.record_stripe_personal_atlas_purchase_v2(text,text,text,timestamptz,text,jsonb)','EXECUTE')
 OR NOT has_function_privilege('service_role','public.record_stripe_personal_atlas_purchase_v2(text,text,text,timestamptz,text,jsonb)','EXECUTE')
 THEN RAISE EXCEPTION 'Billing public gateway ACL absent or exposed: record_stripe_personal_atlas_purchase_v2'; END IF;
  IF to_regprocedure('public.record_stripe_personal_atlas_subscription_state_v2(text,text,text,text,timestamptz,text)') IS NULL
 OR has_function_privilege('anon','public.record_stripe_personal_atlas_subscription_state_v2(text,text,text,text,timestamptz,text)','EXECUTE')
 OR has_function_privilege('authenticated','public.record_stripe_personal_atlas_subscription_state_v2(text,text,text,text,timestamptz,text)','EXECUTE')
 OR NOT has_function_privilege('service_role','public.record_stripe_personal_atlas_subscription_state_v2(text,text,text,text,timestamptz,text)','EXECUTE')
 THEN RAISE EXCEPTION 'Billing public gateway ACL absent or exposed: record_stripe_personal_atlas_subscription_state_v2'; END IF;
END $validation$;
ROLLBACK;
