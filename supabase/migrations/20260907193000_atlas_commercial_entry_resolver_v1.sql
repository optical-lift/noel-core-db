-- Atlas Commercial Entry Resolver v1
--
-- Purpose:
--   establish a minimal canonical public lookup for organization-package referral entry.
--
-- Boundary:
--   the opaque referral token is only a lookup key. It does not encode price,
--   create an organization, create a person, grant authority, or establish an agreement.
--   The resolver returns only currently active public offer facts needed to determine
--   which acquisition encounter Atlas may render.

begin;

create table if not exists atlas.commercial_entry_offers (
  id uuid primary key default gen_random_uuid(),
  stable_key text not null unique,
  offer_kind text not null,
  status text not null default 'active',
  public_title text,
  setup_amount_cents integer,
  recurring_base_amount_cents integer,
  recurring_per_person_amount_cents integer,
  recurring_currency text not null default 'usd',
  recurring_starts_after_days integer not null default 30,
  atlas_setup_included boolean not null default false,
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  constraint commercial_entry_offers_kind_check
    check (offer_kind in ('organization_package')),
  constraint commercial_entry_offers_status_check
    check (status in ('draft','active','retired')),
  constraint commercial_entry_offers_amounts_check
    check (
      coalesce(setup_amount_cents,0) >= 0
      and coalesce(recurring_base_amount_cents,0) >= 0
      and coalesce(recurring_per_person_amount_cents,0) >= 0
      and recurring_starts_after_days >= 0
    )
);

create table if not exists atlas.commercial_entry_referrals (
  id uuid primary key default gen_random_uuid(),
  token text not null unique,
  offer_id uuid not null references atlas.commercial_entry_offers(id) on delete restrict,
  status text not null default 'active',
  affiliate_label text,
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  constraint commercial_entry_referrals_status_check
    check (status in ('active','disabled','retired')),
  constraint commercial_entry_referrals_token_check
    check (length(btrim(token)) between 8 and 120)
);

comment on table atlas.commercial_entry_offers is
  'Canonical commercial acquisition offer definitions. Presentation code may not invent pricing or offer authority outside this custody.';

comment on table atlas.commercial_entry_referrals is
  'Opaque referral/affiliate lookup tokens that select a governed commercial offer. Tokens carry no pricing or domain authority by themselves.';

create index if not exists commercial_entry_referrals_offer_status_idx
  on atlas.commercial_entry_referrals (offer_id, status, valid_from, valid_until);

create or replace function atlas.resolve_commercial_entry_v1(p_ref text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_ref text := btrim(coalesce(p_ref,''));
  v_referral atlas.commercial_entry_referrals%rowtype;
  v_offer atlas.commercial_entry_offers%rowtype;
begin
  if v_ref = '' then
    return null;
  end if;

  select *
  into v_referral
  from atlas.commercial_entry_referrals r
  where r.token = v_ref
    and r.status = 'active'
    and r.valid_from <= now()
    and (r.valid_until is null or r.valid_until >= now())
  limit 1;

  if not found then
    return null;
  end if;

  select *
  into v_offer
  from atlas.commercial_entry_offers o
  where o.id = v_referral.offer_id
    and o.status = 'active'
    and o.valid_from <= now()
    and (o.valid_until is null or o.valid_until >= now())
  limit 1;

  if not found then
    return null;
  end if;

  return jsonb_build_object(
    'entry_kind', 'organization_acquisition',
    'referral_id', v_referral.id,
    'offer_id', v_offer.id,
    'offer_stable_key', v_offer.stable_key,
    'offer_kind', v_offer.offer_kind,
    'public_title', v_offer.public_title,
    'setup_amount_cents', v_offer.setup_amount_cents,
    'recurring_base_amount_cents', v_offer.recurring_base_amount_cents,
    'recurring_per_person_amount_cents', v_offer.recurring_per_person_amount_cents,
    'recurring_currency', v_offer.recurring_currency,
    'recurring_starts_after_days', v_offer.recurring_starts_after_days,
    'atlas_setup_included', v_offer.atlas_setup_included,
    'affiliate_label', v_referral.affiliate_label
  );
end;
$function$;

comment on function atlas.resolve_commercial_entry_v1(text) is
  'Public fail-closed resolver for opaque Atlas commercial-entry referral tokens. Returns only active public offer facts needed to select acquisition encounter. Creates no Person, Organization, Membership, Agreement, payment, or domain truth.';

revoke all on table atlas.commercial_entry_offers from public, anon, authenticated;
revoke all on table atlas.commercial_entry_referrals from public, anon, authenticated;

revoke all on function atlas.resolve_commercial_entry_v1(text) from public;
grant execute on function atlas.resolve_commercial_entry_v1(text) to anon, authenticated, service_role;

insert into atlas.authenticated_rpc_registry (
  signature,
  classification,
  confidence,
  review_status,
  authenticated_execute_expected,
  security_definer_expected,
  service_execute_expected,
  caller_count,
  policy_reference_count,
  evidence,
  anonymous_execute_expected
) values (
  'atlas.resolve_commercial_entry_v1(text)',
  'public_endpoint',
  'verified',
  'active',
  true,
  true,
  true,
  0,
  0,
  jsonb_build_object(
    'source','atlas_commercial_entry_resolver_v1',
    'purpose','Resolve an opaque referral token to the currently active public commercial acquisition offer that governs entry presentation.',
    'boundary','The token is a lookup key only. The function creates no person, organization, membership, agreement, payment, permission, or canonical acquisition answer.',
    'truthBoundary','Only active offer/referral records in Atlas commercial custody may select organization-acquisition entry. Missing, disabled, expired, or retired tokens fail closed to null.',
    'classificationRuleVersion',3
  ),
  true
)
on conflict (signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  anonymous_execute_expected=excluded.anonymous_execute_expected,
  reviewed_at=now();

-- Seed the selected standard organization offer, but do not seed a public referral token.
insert into atlas.commercial_entry_offers (
  stable_key,
  offer_kind,
  status,
  public_title,
  setup_amount_cents,
  recurring_base_amount_cents,
  recurring_per_person_amount_cents,
  recurring_currency,
  recurring_starts_after_days,
  atlas_setup_included,
  metadata
) values (
  'organization_standard_v1',
  'organization_package',
  'active',
  'Atlas organization implementation',
  300000,
  40000,
  1400,
  'usd',
  30,
  true,
  jsonb_build_object(
    'product_map_decision','PMD-019',
    'setup_fee_waived_for_mapped_people',true
  )
)
on conflict (stable_key) do nothing;

commit;
