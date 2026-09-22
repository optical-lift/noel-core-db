begin;

create table if not exists atlas.atlas_service_commercial_price_policies (
  id uuid primary key default gen_random_uuid(),
  price_key text not null unique,
  item_kind text not null
    check (item_kind in (
      'atlas_base_recurring',
      'atlas_initial_setup',
      'ledger_implementation_first_family',
      'ledger_implementation_additional_scope',
      'ledger_recurring',
      'ledger_connection_recurring',
      'commercial_adjustment'
    )),
  charge_kind text not null
    check (charge_kind in ('one_time','recurring')),
  unit_amount_cents integer not null
    check (unit_amount_cents >= 0),
  currency text not null default 'USD'
    check (currency ~ '^[A-Z]{3}$'),
  billing_interval text
    check (billing_interval is null or billing_interval in ('month','year')),
  requires_explicit_election boolean not null default true,
  policy_status text not null default 'active'
    check (policy_status in ('active','transitional','retired')),
  effective_from date not null,
  effective_until date,
  source_note text not null,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (effective_until is null or effective_until>=effective_from),
  check (
    (charge_kind='recurring' and billing_interval is not null)
    or
    (charge_kind='one_time' and billing_interval is null)
  )
);

alter table atlas.atlas_service_commercial_price_policies enable row level security;
revoke all on table atlas.atlas_service_commercial_price_policies
  from public,anon,authenticated,service_role;


create or replace function atlas.guard_atlas_service_commercial_price_policy_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  if new.policy_status in ('active','transitional') and exists(
    select 1
    from atlas.atlas_service_commercial_price_policies p
    where p.id<>new.id
      and p.item_kind=new.item_kind
      and p.policy_status in ('active','transitional')
      and daterange(
        p.effective_from,
        case when p.effective_until is null then null else p.effective_until+1 end,
        '[)'
      ) && daterange(
        new.effective_from,
        case when new.effective_until is null then null else new.effective_until+1 end,
        '[)'
      )
  ) then
    raise exception 'Atlas service price policy overlaps another effective policy for this item kind.'
      using errcode='23514';
  end if;

  new.updated_at:=now();
  return new;
end;
$function$;

drop trigger if exists guard_atlas_service_commercial_price_policy_v1
  on atlas.atlas_service_commercial_price_policies;

create trigger guard_atlas_service_commercial_price_policy_v1
before insert or update on atlas.atlas_service_commercial_price_policies
for each row execute function atlas.guard_atlas_service_commercial_price_policy_v1();


insert into atlas.atlas_service_commercial_price_policies(
  price_key,item_kind,charge_kind,unit_amount_cents,currency,billing_interval,
  requires_explicit_election,policy_status,effective_from,source_note,metadata
) values
(
  'atlas-initial-setup-legacy-v1',
  'atlas_initial_setup','one_time',3995,'USD',null,
  false,'transitional','2026-09-01',
  'Current Personal Atlas checkout setup price; transitional while one-Atlas deferred-settlement acquisition is built.',
  '{"source":"current_personal_atlas_checkout"}'::jsonb
),
(
  'atlas-base-monthly-v1',
  'atlas_base_recurring','recurring',700,'USD','month',
  false,'active','2026-09-01',
  'Current base Atlas monthly price.',
  '{"source":"current_personal_and_organization_pricing"}'::jsonb
),
(
  'ledger-first-family-setup-v1',
  'ledger_implementation_first_family','one_time',300000,'USD',null,
  true,'active','2026-09-01',
  'Current first Ledger implementation/setup price in a highest-parent institutional family.',
  '{"source":"standard_organization_offer_v1"}'::jsonb
),
(
  'ledger-additional-scope-setup-v1',
  'ledger_implementation_additional_scope','one_time',220000,'USD',null,
  true,'active','2026-09-01',
  'Current additional Ledger implementation/setup price beneath the same highest-parent family.',
  '{"source":"standard_organization_offer_v1"}'::jsonb
),
(
  'ledger-monthly-v1',
  'ledger_recurring','recurring',40000,'USD','month',
  true,'active','2026-09-01',
  'Current recurring monthly price for an active Atlas Ledger.',
  '{"source":"standard_organization_offer_v1"}'::jsonb
),
(
  'ledger-connection-monthly-v1',
  'ledger_connection_recurring','recurring',700,'USD','month',
  true,'active','2026-09-01',
  'Current recurring institutional human Connection/access price; separate from the human base Atlas price.',
  '{"source":"standard_organization_offer_v1"}'::jsonb
)
on conflict(price_key) do nothing;


create or replace function atlas.atlas_service_commercial_price_policy_v1(
  p_item_kind text,
  p_at_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_row atlas.atlas_service_commercial_price_policies%rowtype;
  v_count integer;
  v_date date:=coalesce(p_at_date,current_date);
begin
  select count(*)::integer
  into v_count
  from atlas.atlas_service_commercial_price_policies p
  where p.item_kind=p_item_kind
    and p.policy_status in ('active','transitional')
    and p.effective_from<=v_date
    and (p.effective_until is null or p.effective_until>=v_date);

  if v_count<>1 then
    raise exception 'Exactly one effective Atlas service price policy required for item kind %. Found %.',
      p_item_kind,v_count
      using errcode='23514';
  end if;

  select * into v_row
  from atlas.atlas_service_commercial_price_policies p
  where p.item_kind=p_item_kind
    and p.policy_status in ('active','transitional')
    and p.effective_from<=v_date
    and (p.effective_until is null or p.effective_until>=v_date)
  limit 1;

  return jsonb_build_object(
    'contractVersion','atlas_service_commercial_price_policy_v1',
    'pricePolicyId',v_row.id,
    'priceKey',v_row.price_key,
    'itemKind',v_row.item_kind,
    'chargeKind',v_row.charge_kind,
    'unitAmountCents',v_row.unit_amount_cents,
    'currency',v_row.currency,
    'billingInterval',v_row.billing_interval,
    'requiresExplicitElection',v_row.requires_explicit_election,
    'policyStatus',v_row.policy_status,
    'effectiveFrom',v_row.effective_from,
    'effectiveUntil',v_row.effective_until,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'doesNotCreateItem',true,
      'doesNotElect',true,
      'doesNotSettle',true
    )
  );
end;
$function$;

revoke all on function atlas.atlas_service_commercial_price_policy_v1(text,date)
  from public,anon,authenticated;
grant execute on function atlas.atlas_service_commercial_price_policy_v1(text,date)
  to service_role;


insert into atlas.architecture_truth_authorities(
  authority_key,domain_key,truth_question,authority_owner,authority_status,
  canonical_relations,canonical_functions,supporting_relations,
  consumer_surfaces,known_competitors,source_custody,rationale,updated_at
) values (
  'atlas_service_commercial_price_policy',
  'atlas_service_commerce',
  'What is the effective Atlas-service price/election policy for a given commercial item kind at a given date?',
  'atlas_service_commercial_price_policies',
  'transitional',
  array['atlas.atlas_service_commercial_price_policies'],
  array['atlas.atlas_service_commercial_price_policy_v1'],
  array[
    'atlas.personal_atlas_purchases',
    'atlas.implementation_purchases',
    'atlas.ledger_entitlements'
  ],
  array[]::text[],
  array[]::text[],
  'Effective-dated Atlas service pricing policy. Existing UI constants/Stripe prices remain compatibility carriers until acquisition adapters cut over.',
  'Centralizes the semantic price position without making price imply item applicability, election, payer responsibility, settlement, or entitlement.',
  now()
)
on conflict(authority_key) do update set
  domain_key=excluded.domain_key,
  truth_question=excluded.truth_question,
  authority_owner=excluded.authority_owner,
  authority_status=excluded.authority_status,
  canonical_relations=excluded.canonical_relations,
  canonical_functions=excluded.canonical_functions,
  supporting_relations=excluded.supporting_relations,
  consumer_surfaces=excluded.consumer_surfaces,
  known_competitors=excluded.known_competitors,
  source_custody=excluded.source_custody,
  rationale=excluded.rationale,
  updated_at=now();


insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,
  evidence,anonymous_execute_expected
) values (
  'atlas.atlas_service_commercial_price_policy_v1(text,date)',
  'service_internal','verified','active',
  false,true,true,0,1,
  '{"source":"atlas_service_commercial_price_policy_v1","purpose":"Resolve effective Atlas-service price/election policy without creating commercial reality.","classificationRuleVersion":3}'::jsonb,
  false
)
on conflict(signature) do update set
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

commit;
