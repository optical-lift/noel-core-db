begin;

create table if not exists atlas.atlas_service_activation_groups (
  id uuid primary key default gen_random_uuid(),
  composition_id uuid not null
    references atlas.atlas_service_commercial_compositions(id) on delete restrict,
  activation_key text not null,
  activation_kind text not null
    check (activation_kind in ('personal_atlas','ledger_implementation_first_family')),
  state text not null default 'open'
    check (state in ('open','activated')),
  activated_from_settlement_id uuid
    references atlas.atlas_service_settlements(id) on delete restrict,
  personal_atlas_purchase_id uuid
    references atlas.personal_atlas_purchases(id) on delete restrict,
  implementation_purchase_id uuid
    references atlas.implementation_purchases(id) on delete restrict,
  implementation_case_id uuid
    references atlas.implementation_cases(id) on delete restrict,
  ledger_entitlement_id uuid
    references atlas.ledger_entitlements(id) on delete restrict,
  activation_evidence jsonb not null default '{}'::jsonb
    check (jsonb_typeof(activation_evidence)='object'),
  activated_at timestamptz,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint atlas_service_activation_groups_key_uq
    unique (composition_id,activation_key),
  constraint atlas_service_activation_groups_composition_id_uq
    unique (composition_id,id),
  constraint atlas_service_activation_groups_shape_ck
    check (
      (
        state='open'
        and activated_from_settlement_id is null
        and personal_atlas_purchase_id is null
        and implementation_purchase_id is null
        and implementation_case_id is null
        and ledger_entitlement_id is null
        and activated_at is null
      )
      or
      (
        state='activated'
        and activated_from_settlement_id is not null
        and activated_at is not null
        and (
          (
            activation_kind='personal_atlas'
            and personal_atlas_purchase_id is not null
            and implementation_purchase_id is null
            and implementation_case_id is null
            and ledger_entitlement_id is null
          )
          or
          (
            activation_kind='ledger_implementation_first_family'
            and personal_atlas_purchase_id is null
            and implementation_purchase_id is not null
            and implementation_case_id is not null
            and ledger_entitlement_id is not null
          )
        )
      )
    )
);

create unique index if not exists atlas_service_activation_groups_one_personal_uq
  on atlas.atlas_service_activation_groups(composition_id)
  where activation_kind='personal_atlas';

create unique index if not exists atlas_service_activation_groups_one_first_ledger_uq
  on atlas.atlas_service_activation_groups(composition_id)
  where activation_kind='ledger_implementation_first_family';

alter table atlas.atlas_service_activation_groups enable row level security;
revoke all on table atlas.atlas_service_activation_groups
  from public,anon,authenticated,service_role;


alter table atlas.atlas_service_commercial_composition_items
  add column if not exists activation_group_id uuid;

do $ddl$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname='atlas_service_composition_items_activation_group_fk'
      and conrelid='atlas.atlas_service_commercial_composition_items'::regclass
  ) then
    alter table atlas.atlas_service_commercial_composition_items
      add constraint atlas_service_composition_items_activation_group_fk
      foreign key (composition_id,activation_group_id)
      references atlas.atlas_service_activation_groups(composition_id,id)
      on delete restrict;
  end if;
end;
$ddl$;

create index if not exists atlas_service_composition_items_activation_group_idx
  on atlas.atlas_service_commercial_composition_items(activation_group_id)
  where activation_group_id is not null;


alter table atlas.personal_atlas_purchases
  add column if not exists atlas_service_activation_group_id uuid
    references atlas.atlas_service_activation_groups(id) on delete restrict,
  add column if not exists atlas_service_settlement_id uuid
    references atlas.atlas_service_settlements(id) on delete restrict;

alter table atlas.personal_atlas_purchases
  alter column provider_checkout_session_id drop not null;

create unique index if not exists personal_atlas_purchases_activation_group_uq
  on atlas.personal_atlas_purchases(atlas_service_activation_group_id);

do $ddl$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname='personal_atlas_purchases_origin_shape_ck'
      and conrelid='atlas.personal_atlas_purchases'::regclass
  ) then
    alter table atlas.personal_atlas_purchases
      add constraint personal_atlas_purchases_origin_shape_ck
      check (
        (
          provider_checkout_session_id is not null
          and atlas_service_activation_group_id is null
          and atlas_service_settlement_id is null
        )
        or
        (
          provider_checkout_session_id is null
          and atlas_service_activation_group_id is not null
          and atlas_service_settlement_id is not null
        )
      );
  end if;
end;
$ddl$;

comment on column atlas.personal_atlas_purchases.purchaser_email is
  'Legacy purchase/billing contact email. Forward Commercial Composition activation may bind the purchase to an already-known auth user whose authentication email is different; this field is not Person identity authority.';


alter table atlas.implementation_purchases
  add column if not exists atlas_service_activation_group_id uuid
    references atlas.atlas_service_activation_groups(id) on delete restrict,
  add column if not exists atlas_service_settlement_id uuid
    references atlas.atlas_service_settlements(id) on delete restrict;

alter table atlas.implementation_purchases
  alter column provider_checkout_session_id drop not null;

create unique index if not exists implementation_purchases_activation_group_uq
  on atlas.implementation_purchases(atlas_service_activation_group_id);

do $ddl$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname='implementation_purchases_origin_shape_ck'
      and conrelid='atlas.implementation_purchases'::regclass
  ) then
    alter table atlas.implementation_purchases
      add constraint implementation_purchases_origin_shape_ck
      check (
        (
          provider_checkout_session_id is not null
          and atlas_service_activation_group_id is null
          and atlas_service_settlement_id is null
        )
        or
        (
          provider_checkout_session_id is null
          and atlas_service_activation_group_id is not null
          and atlas_service_settlement_id is not null
        )
      );
  end if;
end;
$ddl$;


create or replace function atlas.open_atlas_service_activation_group_service_v1(
  p_composition_id uuid,
  p_activation_key text,
  p_activation_kind text,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_key text:=btrim(coalesce(p_activation_key,''));
  v_group atlas.atlas_service_activation_groups%rowtype;
begin
  if p_composition_id is null or v_key='' then
    raise exception 'Commercial Composition and activation key required.'
      using errcode='22023';
  end if;
  if p_activation_kind not in ('personal_atlas','ledger_implementation_first_family') then
    raise exception 'Unsupported Atlas service activation kind.'
      using errcode='22023';
  end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Activation Group metadata must be a JSON object.'
      using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'atlas-service-activation-group:'||p_composition_id::text||':'||v_key,0
  ));

  select * into v_group
  from atlas.atlas_service_activation_groups
  where composition_id=p_composition_id
    and activation_key=v_key
  limit 1;

  if v_group.id is not null then
    if v_group.activation_kind<>p_activation_kind then
      raise exception 'Activation key already belongs to a different activation kind.'
        using errcode='23505';
    end if;
    return v_group.id;
  end if;

  if not exists(
    select 1
    from atlas.atlas_service_commercial_compositions c
    where c.id=p_composition_id
      and c.status='open'
  ) then
    raise exception 'Open Commercial Composition required.'
      using errcode='23514';
  end if;

  insert into atlas.atlas_service_activation_groups(
    composition_id,activation_key,activation_kind,metadata
  ) values(
    p_composition_id,v_key,p_activation_kind,p_metadata
  )
  returning id into v_group.id;

  return v_group.id;
end;
$function$;

revoke all on function atlas.open_atlas_service_activation_group_service_v1(
  uuid,text,text,jsonb
) from public,anon,authenticated;
grant execute on function atlas.open_atlas_service_activation_group_service_v1(
  uuid,text,text,jsonb
) to service_role;


create or replace function atlas.bind_atlas_service_item_to_activation_group_service_v1(
  p_item_id uuid,
  p_activation_group_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_item atlas.atlas_service_commercial_composition_items%rowtype;
  v_group atlas.atlas_service_activation_groups%rowtype;
begin
  select * into v_item
  from atlas.atlas_service_commercial_composition_items
  where id=p_item_id
  for update;

  select * into v_group
  from atlas.atlas_service_activation_groups
  where id=p_activation_group_id
  for update;

  if v_item.id is null or v_group.id is null then
    raise exception 'Commercial Item and Activation Group required.'
      using errcode='P0002';
  end if;
  if v_group.state<>'open' then
    raise exception 'Only an open Activation Group may receive items.'
      using errcode='23514';
  end if;
  if v_item.composition_id<>v_group.composition_id then
    raise exception 'Activation Group and Item must belong to the same Commercial Composition.'
      using errcode='23514';
  end if;
  if v_item.state not in ('candidate','proposed','elected','settlement_ready') then
    raise exception 'Commercial Item must be grouped before settlement.'
      using errcode='23514';
  end if;
  if v_item.activation_group_id is not null
     and v_item.activation_group_id<>v_group.id then
    raise exception 'Commercial Item already belongs to a different Activation Group.'
      using errcode='23505';
  end if;

  if v_group.activation_kind='personal_atlas'
     and v_item.item_kind not in ('atlas_base_recurring','atlas_initial_setup') then
    raise exception 'Personal Atlas Activation Group accepts only base/setup Atlas items.'
      using errcode='23514';
  end if;

  if v_group.activation_kind='ledger_implementation_first_family'
     and v_item.item_kind not in ('ledger_implementation_first_family','ledger_recurring') then
    raise exception 'First-Ledger Activation Group accepts only setup/recurring Ledger items.'
      using errcode='23514';
  end if;

  if exists(
    select 1
    from atlas.atlas_service_commercial_composition_items i
    where i.activation_group_id=v_group.id
      and i.item_kind=v_item.item_kind
      and i.id<>v_item.id
  ) then
    raise exception 'Activation Group already contains an item of this kind.'
      using errcode='23505';
  end if;

  update atlas.atlas_service_commercial_composition_items
  set activation_group_id=v_group.id,
      updated_at=now()
  where id=v_item.id
  returning * into v_item;

  return jsonb_build_object(
    'itemId',v_item.id,
    'activationGroupId',v_group.id,
    'activationKind',v_group.activation_kind,
    'itemKind',v_item.item_kind
  );
end;
$function$;

revoke all on function atlas.bind_atlas_service_item_to_activation_group_service_v1(
  uuid,uuid
) from public,anon,authenticated;
grant execute on function atlas.bind_atlas_service_item_to_activation_group_service_v1(
  uuid,uuid
) to service_role;


create or replace function atlas.activate_atlas_service_activation_group_service_v1(
  p_activation_group_id uuid,
  p_settlement_id uuid,
  p_activation_evidence jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_group atlas.atlas_service_activation_groups%rowtype;
  v_settlement atlas.atlas_service_settlements%rowtype;
  v_composition atlas.atlas_service_commercial_compositions%rowtype;
  v_payer atlas.atlas_service_payer_profiles%rowtype;
  v_base atlas.atlas_service_commercial_composition_items%rowtype;
  v_setup atlas.atlas_service_commercial_composition_items%rowtype;
  v_recurring atlas.atlas_service_commercial_composition_items%rowtype;
  v_purchase atlas.personal_atlas_purchases%rowtype;
  v_impl_purchase atlas.implementation_purchases%rowtype;
  v_case atlas.implementation_cases%rowtype;
  v_entitlement atlas.ledger_entitlements%rowtype;
  v_bound_count integer;
  v_provider_subscription_id text;
  v_starting_label text;
  v_recurring_starts_at timestamptz;
begin
  if p_activation_group_id is null or p_settlement_id is null then
    raise exception 'Activation Group and successful Settlement required.'
      using errcode='22023';
  end if;
  if p_activation_evidence is null or jsonb_typeof(p_activation_evidence)<>'object' then
    raise exception 'Activation evidence must be a JSON object.'
      using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'atlas-service-forward-activation:'||p_activation_group_id::text,0
  ));

  select * into v_group
  from atlas.atlas_service_activation_groups
  where id=p_activation_group_id
  for update;

  if v_group.id is null then
    raise exception 'Activation Group not found.' using errcode='P0002';
  end if;

  if v_group.state='activated' then
    if v_group.activated_from_settlement_id<>p_settlement_id then
      raise exception 'Activation Group already activated from a different Settlement.'
        using errcode='23505';
    end if;
    return jsonb_strip_nulls(jsonb_build_object(
      'ok',true,
      'alreadyActivated',true,
      'activationGroupId',v_group.id,
      'activationKind',v_group.activation_kind,
      'settlementId',v_group.activated_from_settlement_id,
      'personalAtlasPurchaseId',v_group.personal_atlas_purchase_id,
      'implementationPurchaseId',v_group.implementation_purchase_id,
      'implementationCaseId',v_group.implementation_case_id,
      'ledgerEntitlementId',v_group.ledger_entitlement_id
    ));
  end if;

  select * into v_settlement
  from atlas.atlas_service_settlements
  where id=p_settlement_id
    and state='succeeded';

  if v_settlement.id is null
     or v_settlement.composition_id<>v_group.composition_id then
    raise exception 'Successful Settlement must belong to the Activation Group Commercial Composition.'
      using errcode='23514';
  end if;
  if v_settlement.provider<>'stripe' then
    raise exception 'V1 forward activation supports Stripe settlement only.'
      using errcode='0A000';
  end if;

  select * into v_composition
  from atlas.atlas_service_commercial_compositions
  where id=v_group.composition_id;

  select * into v_payer
  from atlas.atlas_service_payer_profiles
  where id=v_settlement.payer_profile_id
    and composition_id=v_group.composition_id
    and status='active';

  if v_payer.id is null then
    raise exception 'Active Settlement payer is unavailable.'
      using errcode='23514';
  end if;

  select count(*) into v_bound_count
  from atlas.atlas_service_commercial_composition_items
  where activation_group_id=v_group.id;

  if v_bound_count=0 then
    raise exception 'Activation Group must contain at least one Commercial Item.'
      using errcode='23514';
  end if;

  if exists(
    select 1
    from atlas.atlas_service_commercial_composition_items i
    where i.activation_group_id=v_group.id
      and not exists(
        select 1
        from atlas.atlas_service_item_payer_responsibilities r
        where r.composition_item_id=i.id
          and r.payer_profile_id=v_settlement.payer_profile_id
          and r.state='accepted'
      )
  ) then
    raise exception 'Settlement payer must hold accepted responsibility for every Activation Group item.'
      using errcode='23514';
  end if;

  v_provider_subscription_id:=nullif(btrim(coalesce(
    p_activation_evidence->>'providerSubscriptionId',''
  )),'');

  if v_provider_subscription_id is null
     or v_provider_subscription_id !~ '^sub_' then
    raise exception 'Stripe subscription id required for V1 recurring activation.'
      using errcode='22023';
  end if;

  if v_group.activation_kind='personal_atlas' then
    select * into v_base
    from atlas.atlas_service_commercial_composition_items
    where activation_group_id=v_group.id
      and item_kind='atlas_base_recurring'
    limit 1;

    select * into v_setup
    from atlas.atlas_service_commercial_composition_items
    where activation_group_id=v_group.id
      and item_kind='atlas_initial_setup'
    limit 1;

    if v_base.id is null
       or v_base.state not in ('settlement_ready','active')
       or v_base.charge_kind<>'recurring'
       or v_base.billing_interval<>'month'
       or v_base.quantity<>1 then
      raise exception 'Personal Atlas activation requires exactly one elected monthly base item with accepted payer responsibility.'
        using errcode='23514';
    end if;
    if v_bound_count<>(1 + case when v_setup.id is null then 0 else 1 end) then
      raise exception 'Personal Atlas Activation Group contains unsupported items.'
        using errcode='23514';
    end if;
    if v_setup.id is not null then
      if v_setup.state<>'settled'
         or v_setup.charge_kind<>'one_time'
         or not exists(
           select 1
           from atlas.atlas_service_settlement_lines l
           where l.settlement_id=v_settlement.id
             and l.composition_item_id=v_setup.id
         ) then
        raise exception 'Transitional Personal setup item must be successfully settled in the activating Settlement.'
          using errcode='23514';
      end if;
    else
      if v_base.state<>'active'
         or not exists(
           select 1
           from atlas.atlas_service_settlement_lines l
           where l.settlement_id=v_settlement.id
             and l.composition_item_id=v_base.id
         ) then
        raise exception 'Base-only Personal Atlas activation requires the base recurring item itself to be successfully settled.'
          using errcode='23514';
      end if;
    end if;
    if v_composition.auth_user_id is null then
      raise exception 'Personal Atlas forward activation requires an already-known authenticated Atlas human.'
        using errcode='23514';
    end if;
    if nullif(btrim(coalesce(v_payer.billing_email,'')),'') is null then
      raise exception 'Personal Atlas purchase requires canonical payer billing contact evidence.'
        using errcode='23514';
    end if;

    insert into atlas.personal_atlas_purchases(
      provider,provider_checkout_session_id,provider_subscription_id,
      purchaser_email,offer_key,purchase_state,purchased_at,
      claimed_by_user_id,claimed_principal_id,claimed_at,
      atlas_service_activation_group_id,atlas_service_settlement_id,metadata
    ) values(
      v_settlement.provider,null,v_provider_subscription_id,
      lower(btrim(v_payer.billing_email)),'personal_atlas','active',v_settlement.settled_at,
      v_composition.auth_user_id,v_composition.principal_id,v_settlement.settled_at,
      v_group.id,v_settlement.id,
      jsonb_build_object(
        'source','commercial_composition_forward_activation',
        'commercialCompositionId',v_group.composition_id,
        'activationGroupId',v_group.id,
        'settlementId',v_settlement.id,
        'payerProfileId',v_payer.id,
        'billingEmailIsIdentityAuthority',false
      )||p_activation_evidence
    )
    on conflict (atlas_service_activation_group_id) do nothing
    returning * into v_purchase;

    if v_purchase.id is null then
      select * into strict v_purchase
      from atlas.personal_atlas_purchases
      where atlas_service_activation_group_id=v_group.id;

      if v_purchase.atlas_service_settlement_id<>v_settlement.id
         or v_purchase.claimed_by_user_id<>v_composition.auth_user_id
         or v_purchase.provider_subscription_id is distinct from v_provider_subscription_id then
        raise exception 'Existing Personal Atlas forward purchase conflicts with Activation Group evidence.'
          using errcode='23505';
      end if;
    end if;

    if exists(
      select 1
      from atlas.atlas_service_commercial_composition_items
      where activation_group_id=v_group.id
        and personal_atlas_purchase_id is not null
        and personal_atlas_purchase_id<>v_purchase.id
    ) then
      raise exception 'Activation Group already points to a conflicting Personal Atlas Purchase.'
        using errcode='23505';
    end if;

    update atlas.atlas_service_commercial_composition_items
    set personal_atlas_purchase_id=v_purchase.id,
        updated_at=now()
    where activation_group_id=v_group.id;

    update atlas.atlas_service_activation_groups
    set state='activated',
        activated_from_settlement_id=v_settlement.id,
        personal_atlas_purchase_id=v_purchase.id,
        activation_evidence=p_activation_evidence,
        activated_at=now(),
        updated_at=now()
    where id=v_group.id
    returning * into v_group;

    return jsonb_build_object(
      'ok',true,
      'alreadyActivated',false,
      'activationGroupId',v_group.id,
      'activationKind',v_group.activation_kind,
      'settlementId',v_settlement.id,
      'personalAtlasPurchaseId',v_purchase.id,
      'personCreated',false,
      'principalCreated',false,
      'householdCreated',false,
      'organizationCreated',false
    );
  end if;

  if v_group.activation_kind='ledger_implementation_first_family' then
    select * into v_setup
    from atlas.atlas_service_commercial_composition_items
    where activation_group_id=v_group.id
      and item_kind='ledger_implementation_first_family'
    limit 1;

    select * into v_recurring
    from atlas.atlas_service_commercial_composition_items
    where activation_group_id=v_group.id
      and item_kind='ledger_recurring'
    limit 1;

    if v_bound_count<>2
       or v_setup.id is null
       or v_recurring.id is null then
      raise exception 'First-Ledger Activation Group requires exactly setup + recurring Ledger items.'
        using errcode='23514';
    end if;
    if v_setup.state<>'settled'
       or v_setup.charge_kind<>'one_time'
       or v_setup.quantity<>1
       or not v_setup.requires_explicit_election
       or v_setup.election_evidence='{}'::jsonb
       or not exists(
         select 1
         from atlas.atlas_service_settlement_lines l
         where l.settlement_id=v_settlement.id
           and l.composition_item_id=v_setup.id
       ) then
      raise exception 'First-Ledger implementation item lacks settled explicit election in the activating Settlement.'
        using errcode='23514';
    end if;
    if v_recurring.state not in ('settlement_ready','active')
       or v_recurring.charge_kind<>'recurring'
       or v_recurring.billing_interval<>'month'
       or v_recurring.quantity<>1
       or v_recurring.elected_at is null then
      raise exception 'First-Ledger recurring item must be elected monthly commercial authority with accepted payer responsibility.'
        using errcode='23514';
    end if;

    v_starting_label:=nullif(btrim(coalesce(
      p_activation_evidence->>'startingLabel',''
    )),'');
    if v_starting_label is null or length(v_starting_label)>160 then
      raise exception 'Implementation starting label required and must be at most 160 characters.'
        using errcode='22023';
    end if;

    if nullif(p_activation_evidence->>'recurringStartsAt','') is null then
      raise exception 'Governed recurringStartsAt evidence required for first-Ledger activation.'
        using errcode='22023';
    end if;
    v_recurring_starts_at:=(p_activation_evidence->>'recurringStartsAt')::timestamptz;

    insert into atlas.implementation_purchases(
      provider,provider_checkout_session_id,provider_subscription_id,
      offer_key,starting_label,payment_option,purchase_state,currency,
      setup_contract_amount_cents,monthly_ledger_unit_price_cents,
      recurring_starts_at,purchased_at,
      atlas_service_activation_group_id,atlas_service_settlement_id,metadata
    ) values(
      v_settlement.provider,null,v_provider_subscription_id,
      'atlas_ledger_first_family',v_starting_label,'pay_in_full','active',
      lower(v_settlement.currency),
      v_setup.unit_amount_cents*v_setup.quantity,
      v_recurring.unit_amount_cents*v_recurring.quantity,
      v_recurring_starts_at,v_settlement.settled_at,
      v_group.id,v_settlement.id,
      jsonb_build_object(
        'source','commercial_composition_forward_activation',
        'commercialCompositionId',v_group.composition_id,
        'activationGroupId',v_group.id,
        'settlementId',v_settlement.id,
        'payerProfileId',v_payer.id
      )||p_activation_evidence
    )
    on conflict (atlas_service_activation_group_id) do nothing
    returning * into v_impl_purchase;

    if v_impl_purchase.id is null then
      select * into strict v_impl_purchase
      from atlas.implementation_purchases
      where atlas_service_activation_group_id=v_group.id;

      if v_impl_purchase.atlas_service_settlement_id<>v_settlement.id
         or v_impl_purchase.provider_subscription_id is distinct from v_provider_subscription_id
         or v_impl_purchase.setup_contract_amount_cents<>(v_setup.unit_amount_cents*v_setup.quantity)
         or v_impl_purchase.monthly_ledger_unit_price_cents<>(v_recurring.unit_amount_cents*v_recurring.quantity)
         or v_impl_purchase.recurring_starts_at is distinct from v_recurring_starts_at then
        raise exception 'Existing first-Ledger purchase conflicts with Activation Group evidence.'
          using errcode='23505';
      end if;
    end if;

    insert into atlas.implementation_cases(
      implementation_purchase_id,state,metadata
    ) values(
      v_impl_purchase.id,'awaiting_setup_human',
      jsonb_build_object(
        'source','commercial_composition_forward_activation',
        'activationGroupId',v_group.id,
        'settlementId',v_settlement.id
      )
    )
    on conflict (implementation_purchase_id) do nothing
    returning * into v_case;

    if v_case.id is null then
      select * into strict v_case
      from atlas.implementation_cases
      where implementation_purchase_id=v_impl_purchase.id;
    end if;

    insert into atlas.ledger_entitlements(
      implementation_case_id,source_purchase_id,entitlement_number,
      entitlement_kind,price_class,state,setup_price_cents,monthly_price_cents,
      recurring_starts_at,purchased_at,commercial_basis,metadata
    ) values(
      v_case.id,v_impl_purchase.id,1,
      'atlas_ledger','baseline_first','available',
      v_setup.unit_amount_cents*v_setup.quantity,
      v_recurring.unit_amount_cents*v_recurring.quantity,
      v_recurring_starts_at,v_settlement.settled_at,
      jsonb_build_object(
        'source','commercial_composition_forward_activation',
        'activationGroupId',v_group.id,
        'settlementId',v_settlement.id,
        'meaning','Purchased right to establish one baseline governed Ledger scope; institutional reality is not yet established.'
      ),
      p_activation_evidence
    )
    on conflict (implementation_case_id,entitlement_number) do nothing
    returning * into v_entitlement;

    if v_entitlement.id is null then
      select * into strict v_entitlement
      from atlas.ledger_entitlements
      where implementation_case_id=v_case.id
        and entitlement_number=1;

      if v_entitlement.source_purchase_id<>v_impl_purchase.id
         or v_entitlement.setup_price_cents<>(v_setup.unit_amount_cents*v_setup.quantity)
         or v_entitlement.monthly_price_cents<>(v_recurring.unit_amount_cents*v_recurring.quantity)
         or v_entitlement.recurring_starts_at is distinct from v_recurring_starts_at then
        raise exception 'Existing baseline Ledger Entitlement conflicts with Activation Group evidence.'
          using errcode='23505';
      end if;
    end if;

    if exists(
      select 1
      from atlas.atlas_service_commercial_composition_items
      where activation_group_id=v_group.id
        and (
          (implementation_purchase_id is not null and implementation_purchase_id<>v_impl_purchase.id)
          or
          (ledger_entitlement_id is not null and ledger_entitlement_id<>v_entitlement.id)
        )
    ) then
      raise exception 'Activation Group already points to conflicting first-Ledger downstream authority.'
        using errcode='23505';
    end if;

    update atlas.atlas_service_commercial_composition_items
    set implementation_purchase_id=v_impl_purchase.id,
        ledger_entitlement_id=v_entitlement.id,
        updated_at=now()
    where activation_group_id=v_group.id;

    update atlas.atlas_service_activation_groups
    set state='activated',
        activated_from_settlement_id=v_settlement.id,
        implementation_purchase_id=v_impl_purchase.id,
        implementation_case_id=v_case.id,
        ledger_entitlement_id=v_entitlement.id,
        activation_evidence=p_activation_evidence,
        activated_at=now(),
        updated_at=now()
    where id=v_group.id
    returning * into v_group;

    return jsonb_build_object(
      'ok',true,
      'alreadyActivated',false,
      'activationGroupId',v_group.id,
      'activationKind',v_group.activation_kind,
      'settlementId',v_settlement.id,
      'implementationPurchaseId',v_impl_purchase.id,
      'implementationCaseId',v_case.id,
      'ledgerEntitlementId',v_entitlement.id,
      'organizationCreated',false,
      'setupSponsorCreated',false,
      'principalCreated',false,
      'ledgerBindingCreated',false
    );
  end if;

  raise exception 'Unsupported Activation Group kind.'
    using errcode='0A000';
end;
$function$;

revoke all on function atlas.activate_atlas_service_activation_group_service_v1(
  uuid,uuid,jsonb
) from public,anon,authenticated;
grant execute on function atlas.activate_atlas_service_activation_group_service_v1(
  uuid,uuid,jsonb
) to service_role;


create or replace function atlas.begin_personal_atlas_self_api_v1(
  p_name text,
  p_timezone text default 'America/Chicago'::text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_user_id uuid;
  v_email text;
  v_name text;
  v_timezone text;
  v_purchase atlas.personal_atlas_purchases%rowtype;
  v_principal atlas.principals%rowtype;
  v_household atlas.households%rowtype;
  v_implementation_case_id uuid;
  v_implementation_purchase_id uuid;
  v_access_source text;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  v_name:=nullif(trim(p_name),'');
  v_timezone:=coalesce(nullif(trim(p_timezone),''),'America/Chicago');
  if v_name is null then raise exception 'Name required.' using errcode='22023'; end if;
  if not exists(select 1 from pg_timezone_names where name=v_timezone) then raise exception 'Unknown timezone.' using errcode='22023'; end if;

  select lower(email) into v_email from auth.users where id=v_user_id;
  select * into v_principal from atlas.principals where user_id=v_user_id limit 1;
  if v_principal.id is not null then
    return jsonb_build_object(
      'ok',true,
      'alreadyEstablished',true,
      'principalId',v_principal.id,
      'householdId',v_principal.active_household_id
    );
  end if;

  select * into v_purchase
  from atlas.personal_atlas_purchases
  where purchase_state='active'
    and (
      claimed_by_user_id=v_user_id
      or (claimed_by_user_id is null and purchaser_email=v_email)
    )
  order by purchased_at desc,id desc
  limit 1
  for update;

  if v_purchase.id is not null then
    v_access_source := 'personal_atlas_purchase';
  else
    select c.id,p.id
      into v_implementation_case_id,v_implementation_purchase_id
    from atlas.implementation_case_participants sponsor
    join atlas.implementation_cases c on c.id=sponsor.implementation_case_id
    join atlas.implementation_purchases p on p.id=c.implementation_purchase_id
    where sponsor.human_user_id=v_user_id
      and sponsor.relationship_kind='setup_sponsor'
      and sponsor.active
      and c.state not in ('closed','cancelled')
      and p.purchase_state='active'
    order by p.purchased_at desc,c.id desc
    limit 1;

    if v_implementation_case_id is null then
      raise exception 'Active Atlas access required.' using errcode='42501';
    end if;
    v_access_source := 'organization_implementation_setup_sponsor';
  end if;

  insert into atlas.principals(
    user_id,stable_key,name,home_timezone,status,metadata
  ) values(
    v_user_id,
    'person:'||v_user_id::text,
    v_name,
    v_timezone,
    'active',
    jsonb_strip_nulls(jsonb_build_object(
      'source',v_access_source,
      'purchaseId',v_purchase.id,
      'implementationCaseId',v_implementation_case_id,
      'implementationPurchaseId',v_implementation_purchase_id
    ))
  )
  returning * into v_principal;

  insert into atlas.households(
    principal_id,stable_key,name,timezone,status,metadata
  ) values(
    v_principal.id,
    'home',
    'Home',
    v_timezone,
    'active',
    jsonb_strip_nulls(jsonb_build_object(
      'source',v_access_source,
      'purchaseId',v_purchase.id,
      'implementationCaseId',v_implementation_case_id
    ))
  )
  returning * into v_household;

  update atlas.principals
  set active_household_id=v_household.id,
      updated_at=now()
  where id=v_principal.id
  returning * into v_principal;

  insert into atlas.household_members(
    household_id,user_id,display_name,relationship,household_role,active,metadata
  ) values(
    v_household.id,
    v_user_id,
    v_name,
    'self',
    'principal',
    true,
    jsonb_strip_nulls(jsonb_build_object(
      'source',v_access_source,
      'purchaseId',v_purchase.id,
      'implementationCaseId',v_implementation_case_id
    ))
  );

  if v_purchase.id is not null then
    update atlas.personal_atlas_purchases
    set claimed_by_user_id=v_user_id,
        claimed_principal_id=v_principal.id,
        claimed_at=coalesce(claimed_at,now()),
        updated_at=now()
    where id=v_purchase.id;
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'ok',true,
    'alreadyEstablished',false,
    'principalId',v_principal.id,
    'householdId',v_household.id,
    'purchaseId',v_purchase.id,
    'implementationCaseId',v_implementation_case_id,
    'accessBasis',v_access_source
  ));
end;
$function$;

comment on function atlas.begin_personal_atlas_self_api_v1(text,text) is
  'Establishes Personal Atlas identity from an active purchase already claimed to the signed-in human, or from an unclaimed legacy purchase whose billing email matches authentication, or from verified implementation setup-sponsor access. Forward Commercial Composition billing email is not identity authority.';


create or replace function atlas.guard_atlas_service_compatibility_forward_origin_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  if new.personal_atlas_purchase_id is not null
     and exists(
       select 1
       from atlas.personal_atlas_purchases p
       where p.id=new.personal_atlas_purchase_id
         and p.atlas_service_activation_group_id is not null
     ) then
    raise exception 'Forward-activated Personal Atlas Purchase may not be re-imported through acquisition compatibility.'
      using errcode='23514';
  end if;

  if new.implementation_purchase_id is not null
     and exists(
       select 1
       from atlas.implementation_purchases p
       where p.id=new.implementation_purchase_id
         and p.atlas_service_activation_group_id is not null
     ) then
    raise exception 'Forward-activated Implementation Purchase may not be re-imported through acquisition compatibility.'
      using errcode='23514';
  end if;

  return new;
end;
$function$;

revoke all on function atlas.guard_atlas_service_compatibility_forward_origin_v1()
  from public,anon,authenticated,service_role;

drop trigger if exists atlas_service_compatibility_forward_origin_guard
  on atlas.atlas_service_acquisition_compatibility_bindings;

create trigger atlas_service_compatibility_forward_origin_guard
before insert or update of
  personal_atlas_purchase_id,implementation_purchase_id
on atlas.atlas_service_acquisition_compatibility_bindings
for each row
execute function atlas.guard_atlas_service_compatibility_forward_origin_v1();


insert into atlas.architecture_truth_authorities(
  authority_key,domain_key,truth_question,authority_owner,authority_status,
  canonical_relations,canonical_functions,supporting_relations,
  consumer_surfaces,known_competitors,source_custody,rationale,updated_at
) values(
  'atlas_service_settlement_consequence_activation',
  'atlas_service_commerce',
  'Which already-settled Atlas service commercial items may establish which downstream purchase/implementation/entitlement authorities without manufacturing identity or institutional reality?',
  'atlas.atlas_service_activation_groups + item-specific forward activation membrane',
  'incomplete',
  array[
    'atlas.atlas_service_activation_groups',
    'atlas.atlas_service_commercial_composition_items',
    'atlas.personal_atlas_purchases',
    'atlas.implementation_purchases',
    'atlas.implementation_cases',
    'atlas.ledger_entitlements'
  ],
  array[
    'atlas.open_atlas_service_activation_group_service_v1',
    'atlas.bind_atlas_service_item_to_activation_group_service_v1',
    'atlas.activate_atlas_service_activation_group_service_v1',
    'atlas.guard_atlas_service_compatibility_forward_origin_v1'
  ],
  array[
    'atlas.atlas_service_settlements',
    'atlas.atlas_service_settlement_lines',
    'atlas.atlas_service_payer_profiles',
    'atlas.atlas_service_item_payer_responsibilities',
    'atlas.atlas_service_acquisition_compatibility_bindings'
  ],
  array[]::text[],
  array[]::text[],
  'Commercial Composition and Settlement are upstream commercial authority. Activation Group identity controls the bounded crossing into existing purchase/entitlement authorities; billing identity is not Person identity and payment is not institutional truth.',
  'V1 proves forward activation for base Atlas and the first Ledger family. Additional Ledger scope, Connection billing, adjustments, and non-Stripe settlement remain explicitly outside this authority.',
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
  'atlas.open_atlas_service_activation_group_service_v1(uuid,text,text,jsonb)',
  'service_internal','verified','active',
  false,true,true,0,1,
  jsonb_build_object(
    'source','atlas_service_settlement_consequence_activation_v1',
    'purpose','Create/reuse durable grouping for commercial lines that jointly establish one downstream activation consequence.',
    'truthBoundary','Grouping does not settle, purchase, establish identity, or create institutional truth.',
    'classificationRuleVersion',3
  ),
  false
),
(
  'atlas.bind_atlas_service_item_to_activation_group_service_v1(uuid,uuid)',
  'service_internal','verified','active',
  false,true,true,0,1,
  jsonb_build_object(
    'source','atlas_service_settlement_consequence_activation_v1',
    'purpose','Bind an unsettled Composition Item to an explicit compatible Activation Group before settlement.',
    'truthBoundary','Pairing is explicit; no pairing may be inferred from amount, order, payer, or provider metadata.',
    'classificationRuleVersion',3
  ),
  false
),
(
  'atlas.activate_atlas_service_activation_group_service_v1(uuid,uuid,jsonb)',
  'service_internal','verified','active',
  false,true,true,0,1,
  jsonb_build_object(
    'source','atlas_service_settlement_consequence_activation_v1',
    'purpose','Idempotently establish only the downstream commercial authority permitted by a successfully settled Activation Group.',
    'truthBoundary','V1 may create Personal Atlas Purchase or first-Ledger Purchase/Case/Entitlement; it creates no Person, Organization, membership, sponsor, Principal, or Ledger binding.',
    'classificationRuleVersion',3
  ),
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
