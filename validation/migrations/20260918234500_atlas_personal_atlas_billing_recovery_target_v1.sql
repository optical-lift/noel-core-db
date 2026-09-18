do $validation$
declare
  v_user_id uuid := gen_random_uuid();
  v_session_id text := 'cs_test_atlas_billing_recovery_target_v1';
  v_subscription_id text := 'sub_test_atlas_billing_recovery_target_v1';
  v_result jsonb;
begin
  if to_regprocedure('atlas.personal_atlas_billing_recovery_target_service_v1(uuid)') is null then
    raise exception 'Expected Personal Atlas billing recovery target service membrane.';
  end if;

  if has_function_privilege('anon','atlas.personal_atlas_billing_recovery_target_service_v1(uuid)','execute') then
    raise exception 'anon must not execute Personal Atlas billing recovery target lookup.';
  end if;
  if has_function_privilege('authenticated','atlas.personal_atlas_billing_recovery_target_service_v1(uuid)','execute') then
    raise exception 'authenticated must not execute Personal Atlas billing recovery target lookup directly.';
  end if;
  if not has_function_privilege('service_role','atlas.personal_atlas_billing_recovery_target_service_v1(uuid)','execute') then
    raise exception 'service_role must execute Personal Atlas billing recovery target lookup.';
  end if;

  insert into atlas.personal_atlas_purchases(
    provider,
    provider_checkout_session_id,
    provider_subscription_id,
    purchaser_email,
    offer_key,
    purchase_state,
    purchased_at,
    claimed_by_user_id,
    metadata
  ) values (
    'stripe',
    v_session_id,
    v_subscription_id,
    'billing-recovery-proof@example.test',
    'personal_atlas',
    'past_due',
    '2026-09-18T12:00:00Z'::timestamptz,
    v_user_id,
    jsonb_build_object('testMode',true)
  );

  v_result := atlas.personal_atlas_billing_recovery_target_service_v1(v_user_id);

  if coalesce((v_result->>'ok')::boolean,false) is not true
     or v_result->>'providerSubscriptionId' <> v_subscription_id
     or v_result->>'purchaseState' <> 'past_due' then
    raise exception 'Billing recovery target did not resolve the claimed Personal Atlas purchase: %',v_result;
  end if;

  delete from atlas.personal_atlas_purchases
  where provider_checkout_session_id=v_session_id;
end;
$validation$;
