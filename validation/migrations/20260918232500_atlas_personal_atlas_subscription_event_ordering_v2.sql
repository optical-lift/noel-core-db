do $validation$
declare
  v_a_session text := 'cs_test_atlas_lifecycle_current_v2_a';
  v_a_subscription text := 'sub_test_atlas_lifecycle_current_v2_a';
  v_b_session text := 'cs_test_atlas_lifecycle_current_v2_b';
  v_b_subscription text := 'sub_test_atlas_lifecycle_current_v2_b';
  v_c_session text := 'cs_test_atlas_lifecycle_current_v2_c';
  v_c_subscription text := 'sub_test_atlas_lifecycle_current_v2_c';
  v_result jsonb;
  v_state text;
  v_rls boolean;
begin
  if to_regclass('atlas.personal_atlas_subscription_events') is null then
    raise exception 'Expected Personal Atlas subscription Event ledger.';
  end if;
  if to_regclass('atlas.personal_atlas_subscription_observations') is null then
    raise exception 'Expected Personal Atlas current-subscription observation ledger.';
  end if;

  select c.relrowsecurity into v_rls
  from pg_class c
  where c.oid='atlas.personal_atlas_subscription_events'::regclass;
  if not coalesce(v_rls,false) then
    raise exception 'Personal Atlas subscription Event ledger must have RLS enabled.';
  end if;

  select c.relrowsecurity into v_rls
  from pg_class c
  where c.oid='atlas.personal_atlas_subscription_observations'::regclass;
  if not coalesce(v_rls,false) then
    raise exception 'Personal Atlas subscription observation ledger must have RLS enabled.';
  end if;

  if to_regprocedure('atlas.record_stripe_personal_atlas_purchase_v2(text,text,text,timestamptz,text,jsonb)') is null then
    raise exception 'Expected current-provider Personal Atlas purchase recorder v2.';
  end if;
  if to_regprocedure('atlas.record_stripe_personal_atlas_subscription_state_v2(text,text,text,text,timestamptz,text)') is null then
    raise exception 'Expected current-provider Personal Atlas lifecycle recorder v2.';
  end if;

  if has_function_privilege('anon','atlas.record_stripe_personal_atlas_purchase_v2(text,text,text,timestamptz,text,jsonb)','execute')
     or has_function_privilege('authenticated','atlas.record_stripe_personal_atlas_purchase_v2(text,text,text,timestamptz,text,jsonb)','execute') then
    raise exception 'Browser roles must not execute Personal Atlas purchase recorder v2.';
  end if;
  if not has_function_privilege('service_role','atlas.record_stripe_personal_atlas_purchase_v2(text,text,text,timestamptz,text,jsonb)','execute') then
    raise exception 'service_role must execute Personal Atlas purchase recorder v2.';
  end if;

  if has_function_privilege('anon','atlas.record_stripe_personal_atlas_subscription_state_v2(text,text,text,text,timestamptz,text)','execute')
     or has_function_privilege('authenticated','atlas.record_stripe_personal_atlas_subscription_state_v2(text,text,text,text,timestamptz,text)','execute') then
    raise exception 'Browser roles must not execute Personal Atlas lifecycle recorder v2.';
  end if;
  if not has_function_privilege('service_role','atlas.record_stripe_personal_atlas_subscription_state_v2(text,text,text,text,timestamptz,text)','execute') then
    raise exception 'service_role must execute Personal Atlas lifecycle recorder v2.';
  end if;

  -- Historical Checkout replay alone may not reopen a lifecycle-locked Atlas.
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

  select purchase_state into v_state
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

  select purchase_state into v_state
  from atlas.personal_atlas_purchases
  where provider_checkout_session_id=v_a_session;
  if v_state <> 'past_due' then
    raise exception 'Historical Checkout replay reopened a non-current Personal Atlas subscription.';
  end if;

  -- A snapshot Event can be old, delayed, duplicated, or share a timestamp.
  -- Current Stripe Subscription retrieval, not Event.created, decides access.
  v_result := atlas.record_stripe_personal_atlas_subscription_state_v2(
    v_a_subscription,
    'customer.subscription.updated',
    'past_due',
    'evt_test_delayed_old_snapshot',
    '2026-09-18T10:00:10Z'::timestamptz,
    'active'
  );
  if v_result->>'purchaseState' <> 'active'
     or v_result->>'observedStripeStatus' <> 'active' then
    raise exception 'Fresh current Stripe state did not override stale Event snapshot: %',v_result;
  end if;

  v_result := atlas.record_stripe_personal_atlas_subscription_state_v2(
    v_a_subscription,
    'customer.subscription.updated',
    'active',
    'evt_test_same_second_snapshot',
    '2026-09-18T10:00:10Z'::timestamptz,
    'past_due'
  );
  if v_result->>'purchaseState' <> 'past_due' then
    raise exception 'Current provider state was incorrectly inferred from same-second Event evidence: %',v_result;
  end if;

  -- Duplicate Event identity is deduplicated as evidence, but each delivery may
  -- still refresh the current Subscription object and repair the projection.
  v_result := atlas.record_stripe_personal_atlas_subscription_state_v2(
    v_a_subscription,
    'customer.subscription.updated',
    'active',
    'evt_test_same_second_snapshot',
    '2026-09-18T10:00:10Z'::timestamptz,
    'active'
  );
  if coalesce((v_result->>'eventAccepted')::boolean,true) is not false
     or v_result->>'purchaseState' <> 'active' then
    raise exception 'Duplicate Event did not dedupe evidence while refreshing current state: %',v_result;
  end if;

  -- Once a v2 current-provider observation exists, an old deployed v1 caller
  -- cannot overwrite it with snapshot-event status.
  v_result := atlas.record_stripe_personal_atlas_subscription_state_v1(
    v_a_subscription,
    'canceled',
    'evt_test_stale_legacy_cancel'
  );
  if coalesce((v_result->>'legacyIgnored')::boolean,false) is not true
     or v_result->>'purchaseState' <> 'active' then
    raise exception 'Legacy lifecycle call bypassed current-provider observation: %',v_result;
  end if;

  -- A fresh current cancellation locks; a later fresh active observation opens.
  v_result := atlas.record_stripe_personal_atlas_subscription_state_v2(
    v_a_subscription,
    'customer.subscription.deleted',
    'canceled',
    'evt_test_cancel',
    '2026-09-18T10:00:20Z'::timestamptz,
    'canceled'
  );
  if v_result->>'purchaseState' <> 'cancelled' then
    raise exception 'Current Stripe cancellation did not lock Personal Atlas: %',v_result;
  end if;

  v_result := atlas.record_stripe_personal_atlas_subscription_state_v2(
    v_a_subscription,
    'customer.subscription.updated',
    'active',
    'evt_test_recovery',
    '2026-09-18T10:00:30Z'::timestamptz,
    'active'
  );
  if v_result->>'purchaseState' <> 'active' then
    raise exception 'Current Stripe active recovery did not reopen Personal Atlas: %',v_result;
  end if;

  -- Checkout verification v2 itself is also provider-current and replay safe.
  v_result := atlas.record_stripe_personal_atlas_purchase_v2(
    v_a_session,
    v_a_subscription,
    'proof-a@example.test',
    '2026-09-18T10:00:00Z'::timestamptz,
    'canceled',
    jsonb_build_object('source','validation_current_checkout')
  );
  if v_result->>'purchaseState' <> 'cancelled' then
    raise exception 'Current Checkout verification did not honor retrieved cancelled Subscription: %',v_result;
  end if;

  v_result := atlas.record_stripe_personal_atlas_purchase_v2(
    v_a_session,
    v_a_subscription,
    'proof-a@example.test',
    '2026-09-18T10:00:00Z'::timestamptz,
    'active',
    jsonb_build_object('source','validation_current_checkout_recovery')
  );
  if v_result->>'purchaseState' <> 'active' then
    raise exception 'Current Checkout verification did not honor retrieved active Subscription: %',v_result;
  end if;

  -- A current Checkout observation alone must also protect a rollout from a
  -- stale v1 lifecycle caller before the first v2 lifecycle Event arrives.
  v_result := atlas.record_stripe_personal_atlas_purchase_v2(
    v_c_session,
    v_c_subscription,
    'proof-c@example.test',
    '2026-09-18T10:30:00Z'::timestamptz,
    'canceled',
    jsonb_build_object('source','validation_checkout_observation_guard')
  );
  if v_result->>'purchaseState' <> 'cancelled' or nullif(v_result->>'observationId','') is null then
    raise exception 'Current Checkout verification did not persist its provider observation: %',v_result;
  end if;

  v_result := atlas.record_stripe_personal_atlas_subscription_state_v1(
    v_c_subscription,
    'active',
    'evt_test_legacy_after_checkout_observation'
  );
  if coalesce((v_result->>'legacyIgnored')::boolean,false) is not true
     or v_result->>'purchaseState' <> 'cancelled' then
    raise exception 'Legacy lifecycle caller bypassed the current Checkout observation: %',v_result;
  end if;

  -- Lifecycle observation may arrive before Checkout completion. Preserve the
  -- observation and reconcile a later v1 purchase instead of assuming active.
  v_result := atlas.record_stripe_personal_atlas_subscription_state_v2(
    v_b_subscription,
    'customer.subscription.updated',
    'past_due',
    'evt_test_before_purchase',
    '2026-09-18T11:00:00Z'::timestamptz,
    'past_due'
  );
  if coalesce((v_result->>'matched')::boolean,true) is not false then
    raise exception 'Pre-purchase lifecycle observation unexpectedly matched a purchase: %',v_result;
  end if;

  perform atlas.record_stripe_personal_atlas_purchase_v1(
    v_b_session,
    v_b_subscription,
    'proof-b@example.test',
    '2026-09-18T10:59:00Z'::timestamptz,
    jsonb_build_object('source','validation_after_observation')
  );

  select purchase_state into v_state
  from atlas.personal_atlas_purchases
  where provider_checkout_session_id=v_b_session;
  if v_state <> 'past_due' then
    raise exception 'Purchase arriving after current-provider observation failed to reconcile; got %.',v_state;
  end if;

  delete from atlas.personal_atlas_subscription_observations
  where provider_subscription_id in (v_a_subscription,v_b_subscription,v_c_subscription);

  delete from atlas.personal_atlas_subscription_events
  where provider_subscription_id in (v_a_subscription,v_b_subscription,v_c_subscription);

  delete from atlas.personal_atlas_purchases
  where provider_checkout_session_id in (v_a_session,v_b_session,v_c_session);
end;
$validation$;
