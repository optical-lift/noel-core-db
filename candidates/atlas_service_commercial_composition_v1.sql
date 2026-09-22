begin;

create table if not exists atlas.atlas_service_commercial_compositions (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid references auth.users(id) on delete set null,
  principal_id uuid references atlas.principals(id) on delete set null,
  implementation_case_id uuid references atlas.implementation_cases(id) on delete set null,
  status text not null default 'open'
    check (status in ('open','closed')),
  currency text not null default 'USD'
    check (currency ~ '^[A-Z]{3}$'),
  quiet_period_ends_at timestamptz,
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    auth_user_id is not null
    or principal_id is not null
    or implementation_case_id is not null
  ),
  check (
    (status='open' and closed_at is null)
    or
    (status='closed' and closed_at is not null)
  )
);

create index if not exists atlas_service_commercial_compositions_auth_idx
  on atlas.atlas_service_commercial_compositions(auth_user_id)
  where auth_user_id is not null;

create index if not exists atlas_service_commercial_compositions_principal_idx
  on atlas.atlas_service_commercial_compositions(principal_id)
  where principal_id is not null;

create index if not exists atlas_service_commercial_compositions_case_idx
  on atlas.atlas_service_commercial_compositions(implementation_case_id)
  where implementation_case_id is not null;

alter table atlas.atlas_service_commercial_compositions enable row level security;
revoke all on table atlas.atlas_service_commercial_compositions
  from public,anon,authenticated,service_role;


create table if not exists atlas.atlas_service_commercial_composition_items (
  id uuid primary key default gen_random_uuid(),
  composition_id uuid not null
    references atlas.atlas_service_commercial_compositions(id) on delete cascade,
  item_key text not null,
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
  state text not null default 'candidate'
    check (state in (
      'candidate','proposed','elected','settlement_ready',
      'settled','active','withdrawn','adjusted'
    )),
  currency text not null default 'USD'
    check (currency ~ '^[A-Z]{3}$'),
  unit_amount_cents integer not null
    check (unit_amount_cents >= 0),
  quantity integer not null default 1
    check (quantity > 0),
  billing_interval text
    check (billing_interval is null or billing_interval in ('month','year')),
  requires_explicit_election boolean not null default true,
  elected_at timestamptz,
  election_evidence jsonb not null default '{}'::jsonb
    check (jsonb_typeof(election_evidence)='object'),
  personal_atlas_purchase_id uuid
    references atlas.personal_atlas_purchases(id) on delete set null,
  implementation_purchase_id uuid
    references atlas.implementation_purchases(id) on delete set null,
  ledger_entitlement_id uuid
    references atlas.ledger_entitlements(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(composition_id,item_key),
  check (
    (charge_kind='recurring' and billing_interval is not null)
    or
    (charge_kind='one_time' and billing_interval is null)
  ),
  check (
    state not in ('elected','settlement_ready','settled','active')
    or elected_at is not null
  ),
  check (
    not requires_explicit_election
    or state not in ('elected','settlement_ready','settled','active')
    or election_evidence <> '{}'::jsonb
  )
);

alter table atlas.atlas_service_commercial_composition_items enable row level security;
revoke all on table atlas.atlas_service_commercial_composition_items
  from public,anon,authenticated,service_role;


create table if not exists atlas.atlas_service_payer_profiles (
  id uuid primary key default gen_random_uuid(),
  composition_id uuid not null
    references atlas.atlas_service_commercial_compositions(id) on delete cascade,
  payer_kind text not null default 'unknown'
    check (payer_kind in ('unknown','individual','institution','other')),
  display_label text,
  billing_email text,
  canonical_person_id uuid references atlas.people(id) on delete set null,
  canonical_organization_id uuid references atlas.organizations(id) on delete set null,
  provider text,
  provider_customer_id text,
  status text not null default 'active'
    check (status in ('active','inactive')),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists atlas_service_payer_profiles_provider_customer_unique
  on atlas.atlas_service_payer_profiles(provider,provider_customer_id)
  where provider is not null and provider_customer_id is not null;

alter table atlas.atlas_service_payer_profiles enable row level security;
revoke all on table atlas.atlas_service_payer_profiles
  from public,anon,authenticated,service_role;


create table if not exists atlas.atlas_service_item_payer_responsibilities (
  id uuid primary key default gen_random_uuid(),
  composition_item_id uuid not null
    references atlas.atlas_service_commercial_composition_items(id) on delete cascade,
  payer_profile_id uuid not null
    references atlas.atlas_service_payer_profiles(id) on delete cascade,
  state text not null default 'proposed'
    check (state in ('proposed','accepted','ended')),
  acceptance_evidence jsonb not null default '{}'::jsonb
    check (jsonb_typeof(acceptance_evidence)='object'),
  accepted_at timestamptz,
  ended_at timestamptz,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (state='proposed' and accepted_at is null and ended_at is null)
    or
    (state='accepted' and accepted_at is not null and ended_at is null)
    or
    (state='ended' and ended_at is not null)
  ),
  check (
    state<>'accepted'
    or acceptance_evidence <> '{}'::jsonb
  )
);

create unique index if not exists atlas_service_item_payer_active_unique
  on atlas.atlas_service_item_payer_responsibilities(composition_item_id)
  where state='accepted';

alter table atlas.atlas_service_item_payer_responsibilities enable row level security;
revoke all on table atlas.atlas_service_item_payer_responsibilities
  from public,anon,authenticated,service_role;


create table if not exists atlas.atlas_service_settlements (
  id uuid primary key default gen_random_uuid(),
  composition_id uuid not null
    references atlas.atlas_service_commercial_compositions(id) on delete restrict,
  payer_profile_id uuid not null
    references atlas.atlas_service_payer_profiles(id) on delete restrict,
  provider text not null,
  provider_settlement_key text not null,
  state text not null default 'succeeded'
    check (state in ('succeeded')),
  currency text not null default 'USD'
    check (currency ~ '^[A-Z]{3}$'),
  amount_cents integer not null
    check (amount_cents >= 0),
  settled_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  unique(provider,provider_settlement_key)
);

alter table atlas.atlas_service_settlements enable row level security;
revoke all on table atlas.atlas_service_settlements
  from public,anon,authenticated,service_role;


create table if not exists atlas.atlas_service_settlement_lines (
  id uuid primary key default gen_random_uuid(),
  settlement_id uuid not null
    references atlas.atlas_service_settlements(id) on delete restrict,
  composition_item_id uuid not null
    references atlas.atlas_service_commercial_composition_items(id) on delete restrict,
  amount_cents integer not null
    check (amount_cents >= 0),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  unique(settlement_id,composition_item_id)
);

alter table atlas.atlas_service_settlement_lines enable row level security;
revoke all on table atlas.atlas_service_settlement_lines
  from public,anon,authenticated,service_role;


create or replace function atlas.open_atlas_service_commercial_composition_service_v1(
  p_auth_user_id uuid,
  p_principal_id uuid,
  p_implementation_case_id uuid,
  p_currency text,
  p_quiet_period_ends_at timestamptz,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_id uuid;
  v_currency text:=upper(btrim(coalesce(p_currency,'USD')));
begin
  if p_auth_user_id is null
     and p_principal_id is null
     and p_implementation_case_id is null then
    raise exception 'Commercial Composition requires at least one durable journey anchor.'
      using errcode='22023';
  end if;

  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Commercial Composition metadata must be a JSON object.'
      using errcode='22023';
  end if;

  insert into atlas.atlas_service_commercial_compositions(
    auth_user_id,principal_id,implementation_case_id,currency,
    quiet_period_ends_at,metadata
  ) values(
    p_auth_user_id,p_principal_id,p_implementation_case_id,v_currency,
    p_quiet_period_ends_at,p_metadata
  )
  returning id into v_id;

  return v_id;
end;
$function$;

revoke all on function atlas.open_atlas_service_commercial_composition_service_v1(
  uuid,uuid,uuid,text,timestamptz,jsonb
) from public,anon,authenticated;
grant execute on function atlas.open_atlas_service_commercial_composition_service_v1(
  uuid,uuid,uuid,text,timestamptz,jsonb
) to service_role;


create or replace function atlas.add_atlas_service_commercial_candidate_item_service_v1(
  p_composition_id uuid,
  p_item_key text,
  p_item_kind text,
  p_charge_kind text,
  p_unit_amount_cents integer,
  p_quantity integer,
  p_billing_interval text,
  p_requires_explicit_election boolean,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_composition atlas.atlas_service_commercial_compositions%rowtype;
  v_id uuid;
begin
  select * into v_composition
  from atlas.atlas_service_commercial_compositions c
  where c.id=p_composition_id
  for update;

  if v_composition.id is null or v_composition.status<>'open' then
    raise exception 'Open Commercial Composition required.'
      using errcode='23514';
  end if;

  if nullif(btrim(coalesce(p_item_key,'')),'') is null then
    raise exception 'Commercial item key required.' using errcode='22023';
  end if;

  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Commercial item metadata must be a JSON object.'
      using errcode='22023';
  end if;

  insert into atlas.atlas_service_commercial_composition_items(
    composition_id,item_key,item_kind,charge_kind,state,currency,
    unit_amount_cents,quantity,billing_interval,
    requires_explicit_election,metadata
  ) values(
    p_composition_id,btrim(p_item_key),p_item_kind,p_charge_kind,'candidate',
    v_composition.currency,p_unit_amount_cents,coalesce(p_quantity,1),
    p_billing_interval,coalesce(p_requires_explicit_election,true),p_metadata
  )
  returning id into v_id;

  return v_id;
end;
$function$;

revoke all on function atlas.add_atlas_service_commercial_candidate_item_service_v1(
  uuid,text,text,text,integer,integer,text,boolean,jsonb
) from public,anon,authenticated;
grant execute on function atlas.add_atlas_service_commercial_candidate_item_service_v1(
  uuid,text,text,text,integer,integer,text,boolean,jsonb
) to service_role;


create or replace function atlas.propose_atlas_service_commercial_item_service_v1(
  p_item_id uuid,
  p_proposal_evidence jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_item atlas.atlas_service_commercial_composition_items%rowtype;
begin
  if p_proposal_evidence is null or jsonb_typeof(p_proposal_evidence)<>'object' then
    raise exception 'Proposal evidence must be a JSON object.' using errcode='22023';
  end if;

  select * into v_item
  from atlas.atlas_service_commercial_composition_items i
  where i.id=p_item_id
  for update;

  if v_item.id is null then
    raise exception 'Commercial Composition Item not found.' using errcode='P0002';
  end if;

  if v_item.state='candidate' then
    update atlas.atlas_service_commercial_composition_items
    set state='proposed',
        metadata=metadata||jsonb_build_object('proposalEvidence',p_proposal_evidence),
        updated_at=now()
    where id=v_item.id
    returning * into v_item;
  elsif v_item.state<>'proposed' then
    raise exception 'Only candidate/proposed items may be proposed.'
      using errcode='23514';
  end if;

  return jsonb_build_object(
    'itemId',v_item.id,
    'state',v_item.state,
    'requiresExplicitElection',v_item.requires_explicit_election
  );
end;
$function$;

revoke all on function atlas.propose_atlas_service_commercial_item_service_v1(uuid,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.propose_atlas_service_commercial_item_service_v1(uuid,jsonb)
  to service_role;


create or replace function atlas.elect_atlas_service_commercial_item_service_v1(
  p_item_id uuid,
  p_election_evidence jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_item atlas.atlas_service_commercial_composition_items%rowtype;
  v_has_payer boolean:=false;
begin
  if p_election_evidence is null or jsonb_typeof(p_election_evidence)<>'object' then
    raise exception 'Election evidence must be a JSON object.' using errcode='22023';
  end if;

  select * into v_item
  from atlas.atlas_service_commercial_composition_items i
  where i.id=p_item_id
  for update;

  if v_item.id is null then
    raise exception 'Commercial Composition Item not found.' using errcode='P0002';
  end if;

  if v_item.state not in ('proposed','elected','settlement_ready') then
    raise exception 'Only proposed/elected items may be elected.'
      using errcode='23514';
  end if;

  if v_item.requires_explicit_election
     and p_election_evidence='{}'::jsonb then
    raise exception 'Explicit commercial election evidence required.'
      using errcode='23514';
  end if;

  select exists(
    select 1
    from atlas.atlas_service_item_payer_responsibilities r
    join atlas.atlas_service_payer_profiles p on p.id=r.payer_profile_id
    where r.composition_item_id=v_item.id
      and r.state='accepted'
      and p.status='active'
  ) into v_has_payer;

  update atlas.atlas_service_commercial_composition_items
  set state=case when v_has_payer then 'settlement_ready' else 'elected' end,
      elected_at=coalesce(elected_at,now()),
      election_evidence=p_election_evidence,
      updated_at=now()
  where id=v_item.id
  returning * into v_item;

  return jsonb_build_object(
    'itemId',v_item.id,
    'state',v_item.state,
    'electedAt',v_item.elected_at
  );
end;
$function$;

revoke all on function atlas.elect_atlas_service_commercial_item_service_v1(uuid,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.elect_atlas_service_commercial_item_service_v1(uuid,jsonb)
  to service_role;


create or replace function atlas.ensure_atlas_service_payer_profile_service_v1(
  p_composition_id uuid,
  p_payer_kind text,
  p_display_label text,
  p_billing_email text,
  p_canonical_person_id uuid,
  p_canonical_organization_id uuid,
  p_provider text,
  p_provider_customer_id text,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_composition atlas.atlas_service_commercial_compositions%rowtype;
  v_id uuid;
begin
  select * into v_composition
  from atlas.atlas_service_commercial_compositions
  where id=p_composition_id;

  if v_composition.id is null then
    raise exception 'Commercial Composition not found.' using errcode='P0002';
  end if;

  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Payer metadata must be a JSON object.' using errcode='22023';
  end if;

  if nullif(btrim(coalesce(p_provider,'')),'') is not null
     and nullif(btrim(coalesce(p_provider_customer_id,'')),'') is not null then
    select id into v_id
    from atlas.atlas_service_payer_profiles
    where provider=btrim(p_provider)
      and provider_customer_id=btrim(p_provider_customer_id);

    if v_id is not null then
      return v_id;
    end if;
  end if;

  insert into atlas.atlas_service_payer_profiles(
    composition_id,payer_kind,display_label,billing_email,
    canonical_person_id,canonical_organization_id,
    provider,provider_customer_id,metadata
  ) values(
    p_composition_id,coalesce(nullif(btrim(p_payer_kind),''),'unknown'),
    nullif(btrim(coalesce(p_display_label,'')),''),
    nullif(lower(btrim(coalesce(p_billing_email,''))),''),
    p_canonical_person_id,p_canonical_organization_id,
    nullif(btrim(coalesce(p_provider,'')),''),
    nullif(btrim(coalesce(p_provider_customer_id,'')),''),
    p_metadata
  )
  returning id into v_id;

  return v_id;
end;
$function$;

revoke all on function atlas.ensure_atlas_service_payer_profile_service_v1(
  uuid,text,text,text,uuid,uuid,text,text,jsonb
) from public,anon,authenticated;
grant execute on function atlas.ensure_atlas_service_payer_profile_service_v1(
  uuid,text,text,text,uuid,uuid,text,text,jsonb
) to service_role;


create or replace function atlas.accept_atlas_service_item_payer_service_v1(
  p_item_id uuid,
  p_payer_profile_id uuid,
  p_acceptance_evidence jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_item atlas.atlas_service_commercial_composition_items%rowtype;
  v_payer atlas.atlas_service_payer_profiles%rowtype;
  v_resp atlas.atlas_service_item_payer_responsibilities%rowtype;
begin
  if p_acceptance_evidence is null
     or jsonb_typeof(p_acceptance_evidence)<>'object'
     or p_acceptance_evidence='{}'::jsonb then
    raise exception 'Payer acceptance evidence required.' using errcode='23514';
  end if;

  select * into v_item
  from atlas.atlas_service_commercial_composition_items
  where id=p_item_id
  for update;

  if v_item.id is null then
    raise exception 'Commercial Composition Item not found.' using errcode='P0002';
  end if;

  if v_item.state not in ('proposed','elected','settlement_ready') then
    raise exception 'Payer may be accepted only for proposed/elected commercial items.'
      using errcode='23514';
  end if;

  select * into v_payer
  from atlas.atlas_service_payer_profiles
  where id=p_payer_profile_id
    and status='active';

  if v_payer.id is null or v_payer.composition_id<>v_item.composition_id then
    raise exception 'Active payer must belong to the same Commercial Composition.'
      using errcode='23514';
  end if;

  update atlas.atlas_service_item_payer_responsibilities
  set state='ended',ended_at=now(),updated_at=now()
  where composition_item_id=v_item.id
    and state='accepted'
    and payer_profile_id<>v_payer.id;

  select * into v_resp
  from atlas.atlas_service_item_payer_responsibilities
  where composition_item_id=v_item.id
    and payer_profile_id=v_payer.id
    and state='accepted'
  limit 1;

  if v_resp.id is null then
    insert into atlas.atlas_service_item_payer_responsibilities(
      composition_item_id,payer_profile_id,state,
      acceptance_evidence,accepted_at
    ) values(
      v_item.id,v_payer.id,'accepted',
      p_acceptance_evidence,now()
    )
    returning * into v_resp;
  end if;

  if v_item.state in ('elected','settlement_ready') then
    update atlas.atlas_service_commercial_composition_items
    set state='settlement_ready',updated_at=now()
    where id=v_item.id
    returning * into v_item;
  end if;

  return jsonb_build_object(
    'itemId',v_item.id,
    'payerProfileId',v_payer.id,
    'payerResponsibilityId',v_resp.id,
    'itemState',v_item.state
  );
end;
$function$;

revoke all on function atlas.accept_atlas_service_item_payer_service_v1(uuid,uuid,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.accept_atlas_service_item_payer_service_v1(uuid,uuid,jsonb)
  to service_role;


create or replace function atlas.record_atlas_service_settlement_service_v1(
  p_composition_id uuid,
  p_payer_profile_id uuid,
  p_provider text,
  p_provider_settlement_key text,
  p_currency text,
  p_lines jsonb,
  p_settled_at timestamptz,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_existing uuid;
  v_settlement_id uuid;
  v_total integer:=0;
  v_line jsonb;
  v_item atlas.atlas_service_commercial_composition_items%rowtype;
  v_payer_ok boolean;
  v_line_amount integer;
  v_currency text:=upper(btrim(coalesce(p_currency,'USD')));
begin
  if nullif(btrim(coalesce(p_provider,'')),'') is null
     or nullif(btrim(coalesce(p_provider_settlement_key,'')),'') is null then
    raise exception 'Settlement provider and provider settlement key required.'
      using errcode='22023';
  end if;

  if p_lines is null or jsonb_typeof(p_lines)<>'array'
     or jsonb_array_length(p_lines)=0 then
    raise exception 'Settlement requires at least one line.'
      using errcode='22023';
  end if;

  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Settlement metadata must be a JSON object.'
      using errcode='22023';
  end if;

  select id into v_existing
  from atlas.atlas_service_settlements
  where provider=btrim(p_provider)
    and provider_settlement_key=btrim(p_provider_settlement_key);

  if v_existing is not null then
    return v_existing;
  end if;

  if not exists(
    select 1 from atlas.atlas_service_payer_profiles p
    where p.id=p_payer_profile_id
      and p.composition_id=p_composition_id
      and p.status='active'
  ) then
    raise exception 'Settlement payer must be active in the Commercial Composition.'
      using errcode='23514';
  end if;

  for v_line in select value from jsonb_array_elements(p_lines)
  loop
    if jsonb_typeof(v_line)<>'object'
       or nullif(v_line->>'itemId','') is null
       or nullif(v_line->>'amountCents','') is null then
      raise exception 'Each settlement line requires itemId and amountCents.'
        using errcode='22023';
    end if;

    v_line_amount:=(v_line->>'amountCents')::integer;

    if v_line_amount<0 then
      raise exception 'Settlement line amount cannot be negative.'
        using errcode='22023';
    end if;

    select * into v_item
    from atlas.atlas_service_commercial_composition_items i
    where i.id=(v_line->>'itemId')::uuid
    for update;

    if v_item.id is null
       or v_item.composition_id<>p_composition_id
       or v_item.state<>'settlement_ready'
       or v_item.currency<>v_currency then
      raise exception 'Settlement line item must be settlement-ready in the same Composition/currency.'
        using errcode='23514';
    end if;

    select exists(
      select 1
      from atlas.atlas_service_item_payer_responsibilities r
      where r.composition_item_id=v_item.id
        and r.payer_profile_id=p_payer_profile_id
        and r.state='accepted'
    ) into v_payer_ok;

    if not v_payer_ok then
      raise exception 'Settlement payer does not hold accepted responsibility for every line.'
        using errcode='23514';
    end if;

    if exists(
      select 1
      from jsonb_array_elements(p_lines) other
      where other->>'itemId'=v_line->>'itemId'
        and other is distinct from v_line
    ) then
      raise exception 'Settlement may include each Composition Item only once.'
        using errcode='23505';
    end if;

    v_total:=v_total+v_line_amount;
  end loop;

  insert into atlas.atlas_service_settlements(
    composition_id,payer_profile_id,provider,provider_settlement_key,
    state,currency,amount_cents,settled_at,metadata
  ) values(
    p_composition_id,p_payer_profile_id,btrim(p_provider),
    btrim(p_provider_settlement_key),'succeeded',v_currency,v_total,
    coalesce(p_settled_at,now()),p_metadata
  )
  returning id into v_settlement_id;

  for v_line in select value from jsonb_array_elements(p_lines)
  loop
    v_line_amount:=(v_line->>'amountCents')::integer;

    select * into v_item
    from atlas.atlas_service_commercial_composition_items
    where id=(v_line->>'itemId')::uuid
    for update;

    insert into atlas.atlas_service_settlement_lines(
      settlement_id,composition_item_id,amount_cents,metadata
    ) values(
      v_settlement_id,v_item.id,v_line_amount,
      coalesce(v_line->'metadata','{}'::jsonb)
    );

    update atlas.atlas_service_commercial_composition_items
    set state=case when charge_kind='one_time' then 'settled' else 'active' end,
        updated_at=now()
    where id=v_item.id;
  end loop;

  return v_settlement_id;
end;
$function$;

revoke all on function atlas.record_atlas_service_settlement_service_v1(
  uuid,uuid,text,text,text,jsonb,timestamptz,jsonb
) from public,anon,authenticated;
grant execute on function atlas.record_atlas_service_settlement_service_v1(
  uuid,uuid,text,text,text,jsonb,timestamptz,jsonb
) to service_role;


create or replace function atlas.atlas_service_commercial_composition_position_v1(
  p_composition_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
  select jsonb_build_object(
    'contractVersion','atlas_service_commercial_composition_position_v1',
    'compositionId',c.id,
    'status',c.status,
    'currency',c.currency,
    'quietPeriodEndsAt',c.quiet_period_ends_at,
    'counts',jsonb_build_object(
      'candidate',count(i.id) filter (where i.state='candidate'),
      'proposed',count(i.id) filter (where i.state='proposed'),
      'elected',count(i.id) filter (where i.state='elected'),
      'settlementReady',count(i.id) filter (where i.state='settlement_ready'),
      'settled',count(i.id) filter (where i.state='settled'),
      'active',count(i.id) filter (where i.state='active'),
      'withdrawn',count(i.id) filter (where i.state='withdrawn')
    ),
    'settlementReadyOneTimeCents',
      coalesce(sum(i.unit_amount_cents*i.quantity)
        filter (where i.state='settlement_ready' and i.charge_kind='one_time'),0),
    'settlementReadyRecurringMonthlyCents',
      coalesce(sum(i.unit_amount_cents*i.quantity)
        filter (
          where i.state='settlement_ready'
            and i.charge_kind='recurring'
            and i.billing_interval='month'
        ),0),
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'doesNotElect',true,
      'doesNotSettle',true,
      'doesNotActivateEntitlement',true
    )
  )
  from atlas.atlas_service_commercial_compositions c
  left join atlas.atlas_service_commercial_composition_items i
    on i.composition_id=c.id
  where c.id=p_composition_id
  group by c.id;
$function$;

revoke all on function atlas.atlas_service_commercial_composition_position_v1(uuid)
  from public,anon,authenticated,service_role;


insert into atlas.architecture_truth_authorities(
  authority_key,domain_key,truth_question,authority_owner,authority_status,
  canonical_relations,canonical_functions,supporting_relations,
  consumer_surfaces,known_competitors,source_custody,rationale,updated_at
) values
(
  'atlas_service_commercial_composition',
  'atlas_service_commerce',
  'What commercial Atlas/Ledger/Connection obligations have been discovered, proposed, elected, and made settlement-ready without pretending those stages are purchases or entitlements?',
  'atlas_service_commercial_compositions + atlas_service_commercial_composition_items',
  'candidate',
  array[
    'atlas.atlas_service_commercial_compositions',
    'atlas.atlas_service_commercial_composition_items'
  ],
  array[
    'atlas.open_atlas_service_commercial_composition_service_v1',
    'atlas.add_atlas_service_commercial_candidate_item_service_v1',
    'atlas.propose_atlas_service_commercial_item_service_v1',
    'atlas.elect_atlas_service_commercial_item_service_v1',
    'atlas.atlas_service_commercial_composition_position_v1'
  ],
  array[
    'atlas.personal_atlas_purchases',
    'atlas.implementation_purchases',
    'atlas.ledger_entitlements'
  ],
  array[]::text[],
  array[]::text[],
  'Atlas commercial control plane; payment providers and purchase/entitlement authorities remain downstream evidence/owners of their own meanings.',
  'Separates discovery/proposal/election from purchase, settlement, and entitlement activation so one Atlas may discover scope before final commercial composition.',
  now()
),
(
  'atlas_service_payer_responsibility',
  'atlas_service_commerce',
  'Who has accepted financial responsibility for an elected Atlas service commercial item?',
  'atlas_service_payer_profiles + atlas_service_item_payer_responsibilities',
  'candidate',
  array[
    'atlas.atlas_service_payer_profiles',
    'atlas.atlas_service_item_payer_responsibilities'
  ],
  array[
    'atlas.ensure_atlas_service_payer_profile_service_v1',
    'atlas.accept_atlas_service_item_payer_service_v1'
  ],
  array[]::text[],
  array[]::text[],
  array[]::text[],
  'Billing identity is commercial evidence and must not silently establish Person, Principal, Organization, setup sponsor, or institutional authority.',
  'Preserves payer responsibility separately from Atlas identity and institutional identity.',
  now()
),
(
  'atlas_service_settlement',
  'atlas_service_commerce',
  'Which elected Atlas service items were financially settled together for one payer?',
  'atlas_service_settlements + atlas_service_settlement_lines',
  'candidate',
  array[
    'atlas.atlas_service_settlements',
    'atlas.atlas_service_settlement_lines'
  ],
  array[
    'atlas.record_atlas_service_settlement_service_v1'
  ],
  array[
    'atlas.commercial_orders',
    'atlas.commercial_payments'
  ],
  array[]::text[],
  array[]::text[],
  'Provider-backed settlement record over already elected/accepted commercial items; downstream purchase/subscription/entitlement adapters retain their own authority.',
  'Makes batching durable without collapsing independently meaningful line items into one synthetic product.',
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
) values
(
  'atlas.open_atlas_service_commercial_composition_service_v1(uuid,uuid,uuid,text,timestamptz,jsonb)',
  'service_internal','verified','active',false,true,true,0,1,
  '{"source":"atlas_service_commercial_composition_v1","purpose":"Open a pre-settlement Atlas service Commercial Composition without creating purchase/entitlement truth.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.add_atlas_service_commercial_candidate_item_service_v1(uuid,text,text,text,integer,integer,text,boolean,jsonb)',
  'service_internal','verified','active',false,true,true,0,1,
  '{"source":"atlas_service_commercial_composition_v1","purpose":"Add a discovered candidate commercial item without electing or settling it.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.propose_atlas_service_commercial_item_service_v1(uuid,jsonb)',
  'service_internal','verified','active',false,true,true,0,1,
  '{"source":"atlas_service_commercial_composition_v1","purpose":"Move a candidate Atlas service item to proposed state without commercial election.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.elect_atlas_service_commercial_item_service_v1(uuid,jsonb)',
  'service_internal','verified','active',false,true,true,0,1,
  '{"source":"atlas_service_commercial_composition_v1","purpose":"Record an upstream-authorized explicit commercial election; this function does not itself establish user authority.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.ensure_atlas_service_payer_profile_service_v1(uuid,text,text,text,uuid,uuid,text,text,jsonb)',
  'service_internal','verified','active',false,true,true,0,1,
  '{"source":"atlas_service_commercial_composition_v1","purpose":"Preserve payer/billing identity separately from Atlas identity and institutional identity.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.accept_atlas_service_item_payer_service_v1(uuid,uuid,jsonb)',
  'service_internal','verified','active',false,true,true,0,1,
  '{"source":"atlas_service_commercial_composition_v1","purpose":"Record upstream-authorized payer responsibility for one elected/proposed commercial item.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.record_atlas_service_settlement_service_v1(uuid,uuid,text,text,text,jsonb,timestamptz,jsonb)',
  'service_internal','verified','active',false,true,true,0,1,
  '{"source":"atlas_service_commercial_composition_v1","purpose":"Record one successful provider settlement across multiple compatible settlement-ready items for one accepted payer.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.atlas_service_commercial_composition_position_v1(uuid)',
  'service_internal','verified','active',false,true,false,0,1,
  '{"source":"atlas_service_commercial_composition_v1","purpose":"Read current Composition commercial state without electing, settling, or activating entitlement truth.","classificationRuleVersion":3}'::jsonb,
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
