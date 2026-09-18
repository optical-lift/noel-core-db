begin;

-- Personal Atlas billing state must not depend on webhook delivery order.
--
-- Stripe snapshot events are retained as immutable evidence and deduplicated by
-- provider Event id. Access state is projected from a fresh retrieval of the
-- current Stripe Subscription performed by the service when the webhook is
-- handled. Event.created is evidence only and is never used to decide current
-- subscription state.

create table if not exists atlas.personal_atlas_subscription_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null default 'stripe',
  provider_event_id text not null unique,
  provider_event_type text not null,
  provider_subscription_id text not null,
  provider_event_created_at timestamptz not null,
  provider_event_status text not null,
  received_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists personal_atlas_subscription_events_subscription_idx
  on atlas.personal_atlas_subscription_events(
    provider,
    provider_subscription_id,
    received_at desc,
    id desc
  );

create table if not exists atlas.personal_atlas_subscription_observations (
  id uuid primary key default gen_random_uuid(),
  observation_sequence bigint generated always as identity unique,
  provider text not null default 'stripe',
  provider_subscription_id text not null,
  trigger_provider_event_id text not null,
  provider_status text not null,
  purchase_state text not null check (purchase_state in ('active','inactive','cancelled','past_due')),
  observation_kind text not null default 'current_subscription_retrieval',
  observed_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists personal_atlas_subscription_observations_subscription_idx
  on atlas.personal_atlas_subscription_observations(
    provider,
    provider_subscription_id,
    observation_sequence desc
  );

alter table atlas.personal_atlas_subscription_events enable row level security;
alter table atlas.personal_atlas_subscription_observations enable row level security;

comment on table atlas.personal_atlas_subscription_events is
  'Immutable Stripe webhook Event evidence for Personal Atlas subscription lifecycle. Event timestamps do not decide current access state.';
comment on table atlas.personal_atlas_subscription_observations is
  'Service-owned observations of the current Stripe Subscription retrieved while handling billing evidence. These observations project Personal Atlas access state.';

create or replace function atlas.personal_atlas_purchase_state_from_stripe_status_internal_v1(
  p_stripe_status text
)
returns text
language sql
immutable
security invoker
set search_path = pg_catalog
as $function$
  select case lower(coalesce(trim(p_stripe_status),''))
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
$function$;

revoke all on function atlas.personal_atlas_purchase_state_from_stripe_status_internal_v1(text)
  from public,anon,authenticated;

-- Compatibility purchase recorder for the currently deployed Atlas application.
-- Immutable Checkout evidence may refresh descriptive fields, but replaying an
-- old Checkout must never reactivate a purchase whose lifecycle has moved.
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
  v_observation atlas.personal_atlas_subscription_observations%rowtype;
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
    purchase_state=atlas.personal_atlas_purchases.purchase_state,
    purchased_at=excluded.purchased_at,
    metadata=atlas.personal_atlas_purchases.metadata || excluded.metadata,
    updated_at=now()
  returning * into v_purchase;

  -- If current-provider observations already exist (for example a subscription
  -- webhook arrived before Checkout completion), immediately reconcile the new
  -- purchase to the latest observation Atlas actually made of Stripe.
  select *
    into v_observation
  from atlas.personal_atlas_subscription_observations o
  where o.provider='stripe'
    and o.provider_subscription_id=v_purchase.provider_subscription_id
  order by o.observation_sequence desc
  limit 1;

  if v_observation.id is not null then
    update atlas.personal_atlas_purchases
    set purchase_state=v_observation.purchase_state,
        metadata=metadata || jsonb_build_object(
          'latestStripeSubscriptionStatus',v_observation.provider_status,
          'latestStripeSubscriptionObservedAt',v_observation.observed_at,
          'latestStripeSubscriptionObservationKind',v_observation.observation_kind,
          'latestStripeSubscriptionEventId',v_observation.trigger_provider_event_id
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

-- New purchase membrane used when Atlas has freshly retrieved the current
-- Subscription while verifying the Checkout. Unlike v1, replay is allowed to
-- change purchase_state because the supplied status is current provider state,
-- not historical Checkout state.
create or replace function atlas.record_stripe_personal_atlas_purchase_v2(
  p_checkout_session_id text,
  p_subscription_id text,
  p_purchaser_email text,
  p_purchased_at timestamptz,
  p_current_stripe_status text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog,atlas,auth
as $function$
declare
  v_state text;
  v_purchase atlas.personal_atlas_purchases%rowtype;
  v_observation atlas.personal_atlas_subscription_observations%rowtype;
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

  v_state := atlas.personal_atlas_purchase_state_from_stripe_status_internal_v1(p_current_stripe_status);

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
    v_state,
    coalesce(p_purchased_at,now()),
    coalesce(p_metadata,'{}'::jsonb) || jsonb_build_object(
      'latestStripeSubscriptionStatus',lower(coalesce(trim(p_current_stripe_status),'')),
      'latestStripeSubscriptionObservedAt',now(),
      'latestStripeSubscriptionObservationKind','checkout_current_subscription_retrieval'
    )
  )
  on conflict (provider_checkout_session_id) do update set
    provider_subscription_id=excluded.provider_subscription_id,
    purchaser_email=excluded.purchaser_email,
    purchase_state=v_state,
    purchased_at=excluded.purchased_at,
    metadata=atlas.personal_atlas_purchases.metadata || excluded.metadata,
    updated_at=now()
  returning * into v_purchase;

  insert into atlas.personal_atlas_subscription_observations(
    provider,
    provider_subscription_id,
    trigger_provider_event_id,
    provider_status,
    purchase_state,
    observation_kind,
    metadata
  ) values (
    'stripe',
    trim(p_subscription_id),
    'checkout:'||trim(p_checkout_session_id),
    lower(coalesce(trim(p_current_stripe_status),'')),
    v_state,
    'checkout_current_subscription_retrieval',
    jsonb_build_object('purchaseId',v_purchase.id)
  )
  returning * into v_observation;

  update atlas.personal_atlas_purchases
  set metadata=metadata || jsonb_build_object(
        'latestStripeSubscriptionStatus',v_observation.provider_status,
        'latestStripeSubscriptionObservedAt',v_observation.observed_at,
        'latestStripeSubscriptionObservationKind',v_observation.observation_kind
      ),
      updated_at=now()
  where id=v_purchase.id
  returning * into v_purchase;

  return jsonb_build_object(
    'ok',true,
    'purchaseId',v_purchase.id,
    'checkoutSessionId',v_purchase.provider_checkout_session_id,
    'purchaseState',v_purchase.purchase_state,
    'observationId',v_observation.id
  );
end;
$function$;

revoke all on function atlas.record_stripe_personal_atlas_purchase_v2(text,text,text,timestamptz,text,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.record_stripe_personal_atlas_purchase_v2(text,text,text,timestamptz,text,jsonb)
  to service_role;

-- v2 records the immutable Event identity/snapshot, then separately records the
-- current Subscription object Atlas freshly retrieved from Stripe. The current
-- retrieval, not Event.created or arrival order, drives access state.
create or replace function atlas.record_stripe_personal_atlas_subscription_state_v2(
  p_subscription_id text,
  p_event_type text,
  p_event_status text,
  p_event_id text,
  p_event_created_at timestamptz,
  p_current_stripe_status text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog,atlas
as $function$
declare
  v_state text;
  v_inserted integer := 0;
  v_observation atlas.personal_atlas_subscription_observations%rowtype;
  v_purchase atlas.personal_atlas_purchases%rowtype;
begin
  if coalesce(trim(p_subscription_id),'') = '' then
    raise exception 'Stripe subscription id required.' using errcode='22023';
  end if;
  if coalesce(trim(p_event_type),'') = '' then
    raise exception 'Stripe event type required.' using errcode='22023';
  end if;
  if coalesce(trim(p_event_id),'') = '' then
    raise exception 'Stripe event id required.' using errcode='22023';
  end if;
  if p_event_created_at is null then
    raise exception 'Stripe event creation time required as evidence.' using errcode='22023';
  end if;

  v_state := atlas.personal_atlas_purchase_state_from_stripe_status_internal_v1(p_current_stripe_status);

  insert into atlas.personal_atlas_subscription_events(
    provider,
    provider_event_id,
    provider_event_type,
    provider_subscription_id,
    provider_event_created_at,
    provider_event_status,
    metadata
  ) values (
    'stripe',
    trim(p_event_id),
    trim(p_event_type),
    trim(p_subscription_id),
    p_event_created_at,
    lower(coalesce(trim(p_event_status),'')),
    '{}'::jsonb
  )
  on conflict (provider_event_id) do nothing;

  get diagnostics v_inserted = row_count;

  insert into atlas.personal_atlas_subscription_observations(
    provider,
    provider_subscription_id,
    trigger_provider_event_id,
    provider_status,
    purchase_state,
    observation_kind,
    metadata
  ) values (
    'stripe',
    trim(p_subscription_id),
    trim(p_event_id),
    lower(coalesce(trim(p_current_stripe_status),'')),
    v_state,
    'current_subscription_retrieval',
    jsonb_build_object(
      'eventType',trim(p_event_type),
      'eventCreatedAt',p_event_created_at
    )
  )
  returning * into v_observation;

  update atlas.personal_atlas_purchases
  set purchase_state=v_observation.purchase_state,
      metadata=metadata || jsonb_build_object(
        'latestStripeSubscriptionStatus',v_observation.provider_status,
        'latestStripeSubscriptionObservedAt',v_observation.observed_at,
        'latestStripeSubscriptionObservationKind',v_observation.observation_kind,
        'latestStripeSubscriptionEventId',v_observation.trigger_provider_event_id
      ),
      updated_at=now()
  where provider='stripe'
    and provider_subscription_id=trim(p_subscription_id)
  returning * into v_purchase;

  return jsonb_build_object(
    'ok',true,
    'eventAccepted',v_inserted=1,
    'matched',v_purchase.id is not null,
    'purchaseId',v_purchase.id,
    'purchaseState',case when v_purchase.id is null then null else v_purchase.purchase_state end,
    'eventId',trim(p_event_id),
    'observationId',v_observation.id,
    'observedStripeStatus',v_observation.provider_status
  );
end;
$function$;

revoke all on function atlas.record_stripe_personal_atlas_subscription_state_v2(text,text,text,text,timestamptz,text)
  from public,anon,authenticated;
grant execute on function atlas.record_stripe_personal_atlas_subscription_state_v2(text,text,text,text,timestamptz,text)
  to service_role;

-- Compatibility membrane for an older deployed Atlas node. Once a v2 current
-- Subscription observation exists, a historical snapshot-event status cannot
-- overwrite it. Before v2 exists, retain the previous fail-closed behavior.
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
  v_observation atlas.personal_atlas_subscription_observations%rowtype;
  v_purchase atlas.personal_atlas_purchases%rowtype;
begin
  if coalesce(trim(p_subscription_id),'') = '' then
    raise exception 'Stripe subscription id required.' using errcode='22023';
  end if;

  select *
    into v_observation
  from atlas.personal_atlas_subscription_observations o
  where o.provider='stripe'
    and o.provider_subscription_id=trim(p_subscription_id)
  order by o.observation_sequence desc
  limit 1;

  if v_observation.id is not null then
    update atlas.personal_atlas_purchases
    set purchase_state=v_observation.purchase_state,
        metadata=metadata || jsonb_strip_nulls(jsonb_build_object(
          'latestStripeSubscriptionStatus',v_observation.provider_status,
          'latestStripeSubscriptionObservedAt',v_observation.observed_at,
          'latestStripeSubscriptionObservationKind',v_observation.observation_kind,
          'latestStripeSubscriptionEventId',v_observation.trigger_provider_event_id,
          'ignoredLegacyStripeSubscriptionEventId',nullif(trim(p_event_id),'')
        )),
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
      'observationId',v_observation.id
    );
  end if;

  v_state := atlas.personal_atlas_purchase_state_from_stripe_status_internal_v1(p_stripe_status);

  update atlas.personal_atlas_purchases
  set purchase_state=v_state,
      metadata=metadata || jsonb_strip_nulls(jsonb_build_object(
        'latestStripeSubscriptionStatus',lower(coalesce(trim(p_stripe_status),'')),
        'latestStripeSubscriptionEventId',nullif(trim(p_event_id),''),
        'latestStripeSubscriptionObservedAt',now(),
        'latestStripeSubscriptionObservationKind','legacy_event_snapshot'
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
