do $validation$
declare
  v_a_session text := 'cs_test_atlas_lifecycle_ordering_v2_a';
  v_a_subscription text := 'sub_test_atlas_lifecycle_ordering_v2_a';
  v_b_session text := 'cs_test_atlas_lifecycle_ordering_v2_b';
  v_b_subscription text := 'sub_test_atlas_lifecycle_ordering_v2_b';
  v_result jsonb;
  v_state text;
  v_rls boolean;
begin
  if to_regclass('atlas.personal_atlas_subscription_events') is null then
    raise exception 'Expected Personal Atlas subscription event ledger.';
  end if;

  select c.relrowsecurity
    into v_rls
  from pg_class c
  where c.oid='atlas.personal_atlas_subscription_events'::regclass;
  if not coalesce(v_rls,false) then
    raise exception 'Personal Atlas subscription event ledger must have RLS enabled.';
  end if;

  if to_regprocedure('atlas.record_stripe_personal_atlas_subscription_state_v2(text,text,text,timestamptz)') is null then
    raise exception 'Expected ordered Personal Atlas subscription lifecycle command v2.';
  end if;

  if has_function_privilege('anon','atlas.record_stripe_personal_atlas_subscription_state_v2(text,text,text,timestamptz)','execute') then
    raise exception 'anon must not execute Personal Atlas subscription lifecycle v2.';
  end if;
  if has_function_privilege('authenticated','atlas.record_stripe_personal_atlas_subscription_state_v2(text,text,text,timestamptz)','execute') then
    raise exception 'authenticated must not execute Personal Atlas subscription lifecycle v2.';
  end if;
  if not has_function_privilege('service_role','atlas.record_stripe_personal_atlas_subscription_state_v2(text,text,text,timestamptz)','execute') then
    raise exception 'service_role must execute Personal Atlas subscription lifecycle v2.';
  end if;

  -- Historical Checkout verification is immutable evidence. Once lifecycle
  -- state moves away from active, replaying the same Checkout must not reopen it.
  perform atlas.record_stripe_personal_atlas_purchase_v1(
    v_a_session,
    v_a_subscription,
    'proof-a@example.test',
    '2026-09-18T10:00:00Z'::timestamptz,
    jsonb_build_object('source','validation')
  );
  perform atlas.record_stripe_personal_atlas_subscription_state_v1(
    v_a_subscription,
    'past_due',
    'evt_test_legacy_past_due'
  );

  select purchase_state
    into v_state
  from atlas.personal_atlas_purchases
  where provider_checkout_session_id=v_a_session;
  if v_state <> 'past_due' then
    raise exception 'Legacy lifecycle setup expected past_due, got %.',v_state;
  end if;

  perform atlas.record_stripe_personal_atlas_purchase_v1(
    v_a_session,
    v_a_subscription,
    'proof-a@example.test',
    '2026-09-18T10:00:00Z'::timestamptz,
    jsonb_build_object('source','validation_replay')
  );

  select purchase_state
    into v_state
  from atlas.personal_atlas_purchases
  where provider_checkout_session_id=v_a_session;
  if v_state <> 'past_due' then
    raise exception 'Checkout replay reopened a non-current Personal Atlas subscription.';
  end if;

  -- Provider event time, not delivery order, decides the current lifecycle.
  v_result := atlas.record_stripe_personal_atlas_subscription_state_v2(
    v_a_subscription,
    'active',
    'evt_test_newer_active',
    '2026-09-18T10:00:20Z'::timestamptz
  );
  if coalesce((v_result->>'accepted')::boolean,false) is not true
     or v_result->>'purchaseState' <> 'active' then
    raise exception 'Newer active lifecycle event was not accepted/applied: %',v_result;
  end if;

  v_result := atlas.record_stripe_personal_atlas_subscription_state_v2(
    v_a_subscription,
    'past_due',
    'evt_test_older_past_due',
    '2026-09-18T10:00:10Z'::timestamptz
  );
  if v_result->>'purchaseState' <> 'active'
     or v_result->>'appliedEventId' <> 'evt_test_newer_active' then
    raise exception 'Older delayed lifecycle event overwrote newer state: %',v_result;
  end if;

  v_result := atlas.record_stripe_personal_atlas_subscription_state_v2(
    v_a_subscription,
    'past_due',
    'evt_test_older_past_due',
    '2026-09-18T10:00:10Z'::timestamptz
  );
  if coalesce((v_result->>'accepted')::boolean,true) is not false then
    raise exception 'Duplicate Stripe event was not deduplicated: %',v_result;
  end if;

  -- Once ordered v2 evidence exists, a stale legacy v1 caller may not overwrite it.
  v_result := atlas.record_stripe_personal_atlas_subscription_state_v1(
    v_a_subscription,
    'canceled',
    'evt_test_stale_legacy_cancel'
  );
  if coalesce((v_result->>'legacyIgnored')::boolean,false) is not true
     or v_result->>'purchaseState' <> 'active' then
    raise exception 'Legacy lifecycle call bypassed ordered v2 evidence: %',v_result;
  end if;

  v_result := atlas.record_stripe_personal_atlas_subscription_state_v2(
    v_a_subscription,
    'canceled',
    'evt_test_newer_cancel',
    '2026-09-18T10:00:30Z'::timestamptz
  );
  if v_result->>'purchaseState' <> 'cancelled' then
    raise exception 'Newer cancellation did not lock Personal Atlas: %',v_result;
  end if;

  v_result := atlas.record_stripe_personal_atlas_subscription_state_v2(
    v_a_subscription,
    'active',
    'evt_test_newest_recovery',
    '2026-09-18T10:00:40Z'::timestamptz
  );
  if v_result->>'purchaseState' <> 'active' then
    raise exception 'Newer active recovery did not reopen Personal Atlas: %',v_result;
  end if;

  -- A lifecycle event may arrive before Checkout completion. Preserve it and
  -- reconcile the later purchase immediately instead of assuming active.
  v_result := atlas.record_stripe_personal_atlas_subscription_state_v2(
    v_b_subscription,
    'past_due',
    'evt_test_before_purchase',
    '2026-09-18T11:00:00Z'::timestamptz
  );
  if coalesce((v_result->>'matched')::boolean,true) is not false then
    raise exception 'Pre-purchase lifecycle event unexpectedly matched a purchase: %',v_result;
  end if;

  perform atlas.record_stripe_personal_atlas_purchase_v1(
    v_b_session,
    v_b_subscription,
    'proof-b@example.test',
    '2026-09-18T10:59:00Z'::timestamptz,
    jsonb_build_object('source','validation_after_event')
  );

  select purchase_state
    into v_state
  from atlas.personal_atlas_purchases
  where provider_checkout_session_id=v_b_session;
  if v_state <> 'past_due' then
    raise exception 'Purchase arriving after lifecycle evidence failed to reconcile; got %.',v_state;
  end if;

  delete from atlas.personal_atlas_subscription_events
  where provider_event_id in (
    'evt_test_newer_active',
    'evt_test_older_past_due',
    'evt_test_newer_cancel',
    'evt_test_newest_recovery',
    'evt_test_before_purchase'
  );
  delete from atlas.personal_atlas_purchases
  where provider_checkout_session_id in (v_a_session,v_b_session);
end;
$validation$;
