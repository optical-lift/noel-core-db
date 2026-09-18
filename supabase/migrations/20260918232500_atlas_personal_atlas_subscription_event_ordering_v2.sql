begin;

-- Personal Atlas subscription lifecycle evidence must be replay-safe and ordered
-- by Stripe event time, not by Atlas delivery time.
--
-- The immutable event ledger below is service-owned. personal_atlas_purchases
-- remains the compact eligibility projection consumed by Atlas.

create table if not exists atlas.personal_atlas_subscription_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null default 'stripe',
  provider_event_id text not null unique,
  provider_subscription_id text not null,
  provider_event_created_at timestamptz not null,
  provider_status text not null,
  purchase_state text not null check (purchase_state in ('active','inactive','cancelled','past_due')),
  received_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists personal_atlas_subscription_events_subscription_order_idx
  on atlas.personal_atlas_subscription_events(
    provider,
    provider_subscription_id,
    provider_event_created_at desc,
    provider_event_id desc
  );

alter table atlas.personal_atlas_subscription_events enable row level security;

comment on table atlas.personal_atlas_subscription_events is
  'Immutable provider subscription lifecycle evidence for Personal Atlas. Current eligibility is projected onto personal_atlas_purchases from the latest known provider event.';

create or replace function atlas.record_stripe_personal_atlas_purchase_v1(
  p_checkout_session_id text,
  p_subscription_id text,
  p_purchaser_email text,
  p_purchased_at timestamptz,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog,atlas,auth
as $function$
declare
  v_purchase atlas.personal_atlas_purchases%rowtype;
  v_latest_event atlas.personal_atlas_subscription_events%rowtype;
begin
  if coalesce(trim(p_checkout_session_id),'') !~ '^cs_' then
    raise exception 'Valid Stripe Checkout session required.' using errcode='22023';
  end if;
  if coalesce(trim(p_subscription_id),'') = '' then
    raise exception 'Stripe subscription id required.' using errcode='22023';
  end if;
  if position('@' in coalesce(trim(p_purchaser_email),'')) <= 1 then
    raise exception 'Purchaser email required.' using errcode='22023';
  end if;

  insert into atlas.personal_atlas_purchases(
    provider,
    provider_checkout_session_id,
    provider_subscription_id,
    purchaser_email,
    offer_key,
    purchase_state,
    purchased_at,
    metadata
  ) values (
    'stripe',
    trim(p_checkout_session_id),
    trim(p_subscription_id),
    lower(trim(p_purchaser_email)),
    'personal_atlas',
    'active',
    coalesce(p_purchased_at,now()),
    coalesce(p_metadata,'{}'::jsonb)
  )
  on conflict (provider_checkout_session_id) do update set
    provider_subscription_id=excluded.provider_subscription_id,
    purchaser_email=excluded.purchaser_email,
    -- Replaying immutable Checkout evidence must never reopen a subscription
    -- whose lifecycle projection has already moved to another state.
    purchase_state=atlas.personal_atlas_purchases.purchase_state,
    purchased_at=excluded.purchased_at,
    metadata=atlas.personal_atlas_purchases.metadata || excluded.metadata,
    updated_at=now()
  returning * into v_purchase;

  select *
    into v_latest_event
  from atlas.personal_atlas_subscription_events e
  where e.provider='stripe'
    and e.provider_subscription_id=v_purchase.provider_subscription_id
  order by e.provider_event_created_at desc,e.provider_event_id desc
  limit 1;

  if v_latest_event.id is not null then
    update atlas.personal_atlas_purchases
    set purchase_state=v_latest_event.purchase_state,
        metadata=metadata || jsonb_build_object(
          'latestStripeSubscriptionStatus',v_latest_event.provider_status,
          'latestStripeSubscriptionEventId',v_latest_event.provider_event_id,
          'latestStripeSubscriptionEventCreatedAt',v_latest_event.provider_event_created_at,
          'latestStripeSubscriptionObservedAt',v_latest_event.received_at
        ),
        updated_at=now()
    where id=v_purchase.id
    returning * into v_purchase;
  end if;

  return jsonb_build_object(
    'ok',true,
    'purchaseId',v_purchase.id,
    'checkoutSessionId',v_purchase.provider_checkout_session_id,
    'purchaseState',v_purchase.purchase_state
  );
end;
$function$;

revoke all on function atlas.record_stripe_personal_atlas_purchase_v1(text,text,text,timestamptz,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.record_stripe_personal_atlas_purchase_v1(text,text,text,timestamptz,jsonb)
  to service_role;

create or replace function atlas.record_stripe_personal_atlas_subscription_state_v2(
  p_subscription_id text,
  p_stripe_status text,
  p_event_id text,
  p_event_created_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog,atlas
as $function$
declare
  v_state text;
  v_status text;
  v_inserted integer := 0;
  v_latest_event atlas.personal_atlas_subscription_events%rowtype;
  v_purchase atlas.personal_atlas_purchases%rowtype;
begin
  if coalesce(trim(p_subscription_id),'') = '' then
    raise exception 'Stripe subscription id required.' using errcode='22023';
  end if;
  if coalesce(trim(p_event_id),'') = '' then
    raise exception 'Stripe event id required.' using errcode='22023';
  end if;
  if p_event_created_at is null then
    raise exception 'Stripe event creation time required.' using errcode='22023';
  end if;

  v_status := lower(coalesce(trim(p_stripe_status),''));
  v_state := case v_status
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

  insert into atlas.personal_atlas_subscription_events(
    provider,
    provider_event_id,
    provider_subscription_id,
    provider_event_created_at,
    provider_status,
    purchase_state,
    metadata
  ) values (
    'stripe',
    trim(p_event_id),
    trim(p_subscription_id),
    p_event_created_at,
    v_status,
    v_state,
    '{}'::jsonb
  )
  on conflict (provider_event_id) do nothing;

  get diagnostics v_inserted = row_count;

  select *
    into v_latest_event
  from atlas.personal_atlas_subscription_events e
  where e.provider='stripe'
    and e.provider_subscription_id=trim(p_subscription_id)
  order by e.provider_event_created_at desc,e.provider_event_id desc
  limit 1;

  update atlas.personal_atlas_purchases
  set purchase_state=v_latest_event.purchase_state,
      metadata=metadata || jsonb_build_object(
        'latestStripeSubscriptionStatus',v_latest_event.provider_status,
        'latestStripeSubscriptionEventId',v_latest_event.provider_event_id,
        'latestStripeSubscriptionEventCreatedAt',v_latest_event.provider_event_created_at,
        'latestStripeSubscriptionObservedAt',v_latest_event.received_at
      ),
      updated_at=now()
  where provider='stripe'
    and provider_subscription_id=trim(p_subscription_id)
  returning * into v_purchase;

  return jsonb_build_object(
    'ok',true,
    'accepted',v_inserted=1,
    'matched',v_purchase.id is not null,
    'purchaseId',v_purchase.id,
    'purchaseState',case when v_purchase.id is null then null else v_purchase.purchase_state end,
    'appliedEventId',v_latest_event.provider_event_id,
    'appliedEventCreatedAt',v_latest_event.provider_event_created_at
  );
end;
$function$;

revoke all on function atlas.record_stripe_personal_atlas_subscription_state_v2(text,text,text,timestamptz)
  from public,anon,authenticated;
grant execute on function atlas.record_stripe_personal_atlas_subscription_state_v2(text,text,text,timestamptz)
  to service_role;

-- Compatibility membrane for already-deployed Atlas nodes. Before any v2 event
-- exists it preserves the old observed-order behavior. Once v2 evidence exists
-- for a subscription, a stale v1 caller can no longer overwrite that projection.
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
  v_status text;
  v_latest_event atlas.personal_atlas_subscription_events%rowtype;
  v_purchase atlas.personal_atlas_purchases%rowtype;
begin
  if coalesce(trim(p_subscription_id),'') = '' then
    raise exception 'Stripe subscription id required.' using errcode='22023';
  end if;

  select *
    into v_latest_event
  from atlas.personal_atlas_subscription_events e
  where e.provider='stripe'
    and e.provider_subscription_id=trim(p_subscription_id)
  order by e.provider_event_created_at desc,e.provider_event_id desc
  limit 1;

  if v_latest_event.id is not null then
    update atlas.personal_atlas_purchases
    set purchase_state=v_latest_event.purchase_state,
        metadata=metadata || jsonb_build_object(
          'latestStripeSubscriptionStatus',v_latest_event.provider_status,
          'latestStripeSubscriptionEventId',v_latest_event.provider_event_id,
          'latestStripeSubscriptionEventCreatedAt',v_latest_event.provider_event_created_at,
          'latestStripeSubscriptionObservedAt',v_latest_event.received_at,
          'ignoredLegacyStripeSubscriptionEventId',nullif(trim(p_event_id),'')
        ),
        updated_at=now()
    where provider='stripe'
      and provider_subscription_id=trim(p_subscription_id)
    returning * into v_purchase;

    return jsonb_build_object(
      'ok',true,
      'matched',v_purchase.id is not null,
      'purchaseId',v_purchase.id,
      'purchaseState',case when v_purchase.id is null then null else v_purchase.purchase_state end,
      'legacyIgnored',true,
      'appliedEventId',v_latest_event.provider_event_id
    );
  end if;

  v_status := lower(coalesce(trim(p_stripe_status),''));
  v_state := case v_status
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
        'latestStripeSubscriptionStatus',v_status,
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
    'purchaseState',case when v_purchase.id is null then null else v_state end,
    'legacyIgnored',false
  );
end;
$function$;

revoke all on function atlas.record_stripe_personal_atlas_subscription_state_v1(text,text,text)
  from public,anon,authenticated;
grant execute on function atlas.record_stripe_personal_atlas_subscription_state_v1(text,text,text)
  to service_role;

commit;
