begin;

-- Atlas implementation purchase + case kernel v1
--
-- Commercial purchase is not institutional truth. A completed Stripe purchase begins
-- an implementation engagement and creates addressable commercial entitlements only.
-- Organization, Organization Unit, Principal, membership, responsibility, authority,
-- permission, and Personal Atlas remain separate later relationships.

create table if not exists atlas.implementation_purchases (
  id uuid primary key default gen_random_uuid(),
  provider text not null default 'stripe' check (provider in ('stripe')),
  provider_checkout_session_id text not null,
  provider_subscription_id text,
  offer_key text not null,
  starting_label text not null,
  payment_option text not null check (payment_option in ('pay_in_full','three_installments')),
  purchase_state text not null default 'active'
    check (purchase_state in ('active','partially_refunded','refunded','disputed','cancelled')),
  currency text not null default 'usd' check (currency ~ '^[a-z]{3}$'),
  setup_contract_amount_cents integer not null check (setup_contract_amount_cents >= 0),
  monthly_ledger_unit_price_cents integer not null check (monthly_ledger_unit_price_cents >= 0),
  recurring_starts_at timestamptz,
  purchased_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint implementation_purchases_checkout_nonblank check (btrim(provider_checkout_session_id) <> ''),
  constraint implementation_purchases_offer_nonblank check (btrim(offer_key) <> ''),
  constraint implementation_purchases_starting_label_nonblank check (btrim(starting_label) <> '' and length(btrim(starting_label)) <= 160),
  constraint implementation_purchases_provider_checkout_uq unique (provider, provider_checkout_session_id)
);

comment on table atlas.implementation_purchases is
  'Durable commercial evidence that an Atlas implementation engagement was purchased. It is not Organization identity, ownership, membership, Principal identity, authority, or a Ledger binding.';
comment on column atlas.implementation_purchases.starting_label is
  'Customer-supplied intake label for the implementation starting point. It is evidence, not canonical Organization or Organization Unit identity.';

create table if not exists atlas.implementation_cases (
  id uuid primary key default gen_random_uuid(),
  implementation_purchase_id uuid not null unique references atlas.implementation_purchases(id) on delete restrict,
  state text not null default 'awaiting_setup_human'
    check (state in ('awaiting_setup_human','ready_for_practitioner','in_implementation','partially_active','active','closed','cancelled')),
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint implementation_cases_close_shape check ((state='closed' and closed_at is not null) or (state<>'closed')),
  constraint implementation_cases_case_purchase_uq unique (id, implementation_purchase_id)
);

comment on table atlas.implementation_cases is
  'Operational container for one paid Atlas implementation engagement. The case may eventually govern several Ledger entitlements/scopes without becoming an Organization itself.';

create table if not exists atlas.implementation_case_participants (
  id uuid primary key default gen_random_uuid(),
  implementation_case_id uuid not null references atlas.implementation_cases(id) on delete cascade,
  human_user_id uuid not null references auth.users(id) on delete restrict,
  relationship_kind text not null check (relationship_kind in ('setup_sponsor','practitioner')),
  active boolean not null default true,
  verified_at timestamptz,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  basis jsonb not null default '{}'::jsonb check (jsonb_typeof(basis)='object'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint implementation_case_participants_active_shape check ((active and ended_at is null) or (not active and ended_at is not null)),
  constraint implementation_case_participants_setup_verified check (relationship_kind <> 'setup_sponsor' or verified_at is not null),
  constraint implementation_case_participants_case_id_uq unique (implementation_case_id, id)
);

comment on table atlas.implementation_case_participants is
  'Case-scoped human relationships for setup sponsorship or Atlas practitioner work. These relationships do not create Organization membership, employment, ownership, Principal status, Decision Authority, or application permission.';

create unique index if not exists implementation_case_one_active_setup_sponsor_uq
  on atlas.implementation_case_participants (implementation_case_id)
  where relationship_kind='setup_sponsor' and active;
create index if not exists implementation_case_participants_human_active_idx
  on atlas.implementation_case_participants (human_user_id, relationship_kind, started_at desc)
  where active;

create table if not exists atlas.ledger_entitlements (
  id uuid primary key default gen_random_uuid(),
  implementation_case_id uuid not null references atlas.implementation_cases(id) on delete restrict,
  source_purchase_id uuid references atlas.implementation_purchases(id) on delete restrict,
  entitlement_number integer not null check (entitlement_number > 0),
  entitlement_kind text not null default 'atlas_ledger' check (entitlement_kind in ('atlas_ledger')),
  price_class text not null default 'baseline_first'
    check (price_class in ('baseline_first','additional_same_family','other_governed')),
  state text not null default 'available'
    check (state in ('available','reserved','bound','activated','retired','refunded')),
  setup_price_cents integer not null check (setup_price_cents >= 0),
  monthly_price_cents integer not null check (monthly_price_cents >= 0),
  recurring_starts_at timestamptz,
  purchased_at timestamptz not null default now(),
  retired_at timestamptz,
  commercial_basis jsonb not null default '{}'::jsonb check (jsonb_typeof(commercial_basis)='object'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ledger_entitlements_case_number_uq unique (implementation_case_id, entitlement_number),
  constraint ledger_entitlements_case_id_uq unique (implementation_case_id, id),
  constraint ledger_entitlements_retired_shape check ((state in ('retired','refunded') and retired_at is not null) or (state not in ('retired','refunded')))
);

comment on table atlas.ledger_entitlements is
  'Purchased right to establish one governed Atlas Ledger scope. An entitlement is commercial state and must not visually or semantically masquerade as an established Organization Ledger before binding.';

create table if not exists atlas.ledger_entitlement_bindings (
  id uuid primary key default gen_random_uuid(),
  implementation_case_id uuid not null,
  ledger_entitlement_id uuid not null,
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  organization_unit_id uuid,
  bound_by_participant_id uuid not null,
  state text not null default 'bound' check (state in ('reserved','bound','activated','ended')),
  bound_at timestamptz not null default now(),
  activated_at timestamptz,
  ended_at timestamptz,
  binding_basis jsonb not null default '{}'::jsonb check (jsonb_typeof(binding_basis)='object'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ledger_entitlement_bindings_case_entitlement_fk
    foreign key (implementation_case_id, ledger_entitlement_id)
    references atlas.ledger_entitlements(implementation_case_id, id)
    on delete restrict,
  constraint ledger_entitlement_bindings_case_participant_fk
    foreign key (implementation_case_id, bound_by_participant_id)
    references atlas.implementation_case_participants(implementation_case_id, id)
    on delete restrict,
  constraint ledger_entitlement_bindings_unit_org_fk
    foreign key (organization_id, organization_unit_id)
    references atlas.organization_units(organization_id, id)
    on delete restrict,
  constraint ledger_entitlement_bindings_activation_shape check (
    (state='activated' and activated_at is not null and ended_at is null)
    or (state='ended' and ended_at is not null)
    or (state in ('reserved','bound') and activated_at is null and ended_at is null)
  )
);

comment on table atlas.ledger_entitlement_bindings is
  'Historical binding of a purchased Ledger entitlement to one independently governable institutional scope. organization_unit_id NULL means the whole Organization; non-NULL narrows the Ledger to that Organization Unit. A Ledger is therefore not synonymous with a company, department, software account, or portfolio object.';

create unique index if not exists ledger_entitlement_bindings_one_live_per_entitlement_uq
  on atlas.ledger_entitlement_bindings (ledger_entitlement_id)
  where ended_at is null;
create unique index if not exists ledger_entitlement_bindings_one_live_org_scope_uq
  on atlas.ledger_entitlement_bindings (organization_id)
  where organization_unit_id is null and ended_at is null;
create unique index if not exists ledger_entitlement_bindings_one_live_unit_scope_uq
  on atlas.ledger_entitlement_bindings (organization_id, organization_unit_id)
  where organization_unit_id is not null and ended_at is null;

-- The direct organization purchase path creates commercial state only. It is deliberately
-- idempotent on the Stripe Checkout Session and refuses to reinterpret an existing purchase.
create or replace function atlas.record_stripe_implementation_purchase_v1(
  p_checkout_session_id text,
  p_subscription_id text,
  p_offer_key text,
  p_starting_label text,
  p_payment_option text,
  p_setup_contract_amount_cents integer,
  p_monthly_ledger_unit_price_cents integer,
  p_recurring_starts_at timestamptz,
  p_purchased_at timestamptz default now(),
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
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
  if p_payment_option not in ('pay_in_full','three_installments') then
    raise exception 'Unsupported payment option.' using errcode='22023';
  end if;
  if p_setup_contract_amount_cents is null or p_setup_contract_amount_cents < 0
     or p_monthly_ledger_unit_price_cents is null or p_monthly_ledger_unit_price_cents < 0 then
    raise exception 'Commercial amounts must be non-negative.' using errcode='22023';
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
      'meaning','One baseline Ledger entitlement; no institutional scope established yet.'
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

comment on function atlas.record_stripe_implementation_purchase_v1(text,text,text,text,text,integer,integer,timestamptz,timestamptz,jsonb) is
  'Service-only idempotent writer for a verified direct Stripe organization purchase. Creates commercial purchase evidence, one Implementation Case, and one baseline Ledger entitlement; creates no Organization, Unit, Principal, membership, authority, permission, or Personal Atlas.';

-- After the designated setup email has been verified through Atlas authentication,
-- attach that authenticated human to the case only. This still creates no institutional relation.
create or replace function atlas.attach_verified_implementation_setup_sponsor_v1(
  p_checkout_session_id text,
  p_human_user_id uuid,
  p_verification_basis jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_case_id uuid;
  v_participant_id uuid;
  v_existing_human uuid;
begin
  if p_human_user_id is null then
    raise exception 'Human user id required.' using errcode='22023';
  end if;
  if p_verification_basis is null or jsonb_typeof(p_verification_basis) <> 'object' then
    raise exception 'Verification basis must be a JSON object.' using errcode='22023';
  end if;

  if not exists (
    select 1 from auth.users u
    where u.id=p_human_user_id
      and u.deleted_at is null
      and (u.banned_until is null or u.banned_until <= now())
  ) then
    raise exception 'Verified Atlas human is unavailable.' using errcode='42501';
  end if;

  select c.id into v_case_id
  from atlas.implementation_purchases p
  join atlas.implementation_cases c on c.implementation_purchase_id=p.id
  where p.provider='stripe'
    and p.provider_checkout_session_id=p_checkout_session_id
    and p.purchase_state='active';

  if v_case_id is null then
    raise exception 'Active implementation purchase/case not found.' using errcode='23503';
  end if;

  select human_user_id, id into v_existing_human, v_participant_id
  from atlas.implementation_case_participants
  where implementation_case_id=v_case_id
    and relationship_kind='setup_sponsor'
    and active
  limit 1;

  if v_participant_id is not null and v_existing_human <> p_human_user_id then
    raise exception 'A different verified setup sponsor is already active for this implementation case.' using errcode='23505';
  end if;

  if v_participant_id is null then
    insert into atlas.implementation_case_participants (
      implementation_case_id, human_user_id, relationship_kind, active,
      verified_at, basis, metadata
    ) values (
      v_case_id, p_human_user_id, 'setup_sponsor', true,
      now(), p_verification_basis,
      jsonb_build_object('source','attach_verified_implementation_setup_sponsor_v1')
    ) returning id into v_participant_id;
  end if;

  update atlas.implementation_cases
  set state = case when state='awaiting_setup_human' then 'ready_for_practitioner' else state end,
      updated_at=now()
  where id=v_case_id;

  return jsonb_build_object(
    'implementationCaseId',v_case_id,
    'setupSponsorParticipantId',v_participant_id,
    'humanUserId',p_human_user_id,
    'relationship','setup_sponsor',
    'membershipCreated',false,
    'principalCreated',false,
    'organizationCreated',false
  );
end;
$function$;

comment on function atlas.attach_verified_implementation_setup_sponsor_v1(text,uuid,jsonb) is
  'Service-only writer that attaches an already-authenticated human as the verified setup sponsor for a purchased implementation case. Setup sponsorship is case-scoped and is not ownership, employment, Organization membership, Principal identity, Decision Authority, or permission.';

alter table atlas.implementation_purchases enable row level security;
alter table atlas.implementation_cases enable row level security;
alter table atlas.implementation_case_participants enable row level security;
alter table atlas.ledger_entitlements enable row level security;
alter table atlas.ledger_entitlement_bindings enable row level security;

revoke all on table atlas.implementation_purchases from public, anon, authenticated;
revoke all on table atlas.implementation_cases from public, anon, authenticated;
revoke all on table atlas.implementation_case_participants from public, anon, authenticated;
revoke all on table atlas.ledger_entitlements from public, anon, authenticated;
revoke all on table atlas.ledger_entitlement_bindings from public, anon, authenticated;

grant select, insert, update, delete on table atlas.implementation_purchases to service_role;
grant select, insert, update, delete on table atlas.implementation_cases to service_role;
grant select, insert, update, delete on table atlas.implementation_case_participants to service_role;
grant select, insert, update, delete on table atlas.ledger_entitlements to service_role;
grant select, insert, update, delete on table atlas.ledger_entitlement_bindings to service_role;

revoke all on function atlas.record_stripe_implementation_purchase_v1(text,text,text,text,text,integer,integer,timestamptz,timestamptz,jsonb) from public, anon, authenticated;
grant execute on function atlas.record_stripe_implementation_purchase_v1(text,text,text,text,text,integer,integer,timestamptz,timestamptz,jsonb) to service_role;

revoke all on function atlas.attach_verified_implementation_setup_sponsor_v1(text,uuid,jsonb) from public, anon, authenticated;
grant execute on function atlas.attach_verified_implementation_setup_sponsor_v1(text,uuid,jsonb) to service_role;

commit;
