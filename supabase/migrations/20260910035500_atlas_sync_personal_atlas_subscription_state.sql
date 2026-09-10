-- Keep Personal Atlas purchase eligibility aligned with Stripe subscription lifecycle evidence.
-- Service custody only; browser callers cannot mutate purchase state.
-- Unknown Stripe states fail closed to inactive rather than preserving stale paid eligibility.

create or replace function atlas.record_stripe_personal_atlas_subscription_state_v1(
  p_subscription_id text,
  p_stripe_status text,
  p_event_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog,atlas
as $function$
declare
  v_state text;
  v_purchase atlas.personal_atlas_purchases%rowtype;
begin
  if coalesce(trim(p_subscription_id),'') = '' then
    raise exception 'Stripe subscription id required.' using errcode='22023';
  end if;

  v_state := case lower(coalesce(trim(p_stripe_status),''))
    when 'active' then 'active'
    when 'trialing' then 'active'
    when 'past_due' then 'past_due'
    when 'unpaid' then 'past_due'
    when 'canceled' then 'cancelled'
    when 'incomplete' then 'inactive'
    when 'incomplete_expired' then 'inactive'
    when 'paused' then 'inactive'
    else 'inactive'
  end;

  update atlas.personal_atlas_purchases
  set purchase_state=v_state,
      metadata=metadata || jsonb_strip_nulls(jsonb_build_object(
        'latestStripeSubscriptionStatus',lower(coalesce(trim(p_stripe_status),'')),
        'latestStripeSubscriptionEventId',nullif(trim(p_event_id),''),
        'latestStripeSubscriptionObservedAt',now()
      )),
      updated_at=now()
  where provider='stripe'
    and provider_subscription_id=trim(p_subscription_id)
  returning * into v_purchase;

  return jsonb_build_object(
    'ok',true,
    'matched',v_purchase.id is not null,
    'purchaseId',v_purchase.id,
    'purchaseState',case when v_purchase.id is null then null else v_state end
  );
end;
$function$;

revoke all on function atlas.record_stripe_personal_atlas_subscription_state_v1(text,text,text) from public,anon,authenticated;
grant execute on function atlas.record_stripe_personal_atlas_subscription_state_v1(text,text,text) to service_role;
