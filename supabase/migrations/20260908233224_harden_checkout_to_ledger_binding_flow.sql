-- Unambiguous public service membranes for Stripe -> canonical implementation writes.
create or replace function public.record_stripe_implementation_purchase_v1(
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
) returns jsonb
language sql
security definer
set search_path = pg_catalog
as $$
  select atlas.record_stripe_implementation_purchase_v1(
    p_checkout_session_id,
    p_subscription_id,
    p_offer_key,
    p_starting_label,
    p_payment_option,
    p_setup_contract_amount_cents,
    p_monthly_ledger_unit_price_cents,
    p_recurring_starts_at,
    p_purchased_at,
    p_metadata
  );
$$;
revoke all on function public.record_stripe_implementation_purchase_v1(text,text,text,text,text,integer,integer,timestamptz,timestamptz,jsonb) from public, anon, authenticated;
grant execute on function public.record_stripe_implementation_purchase_v1(text,text,text,text,text,integer,integer,timestamptz,timestamptz,jsonb) to service_role;

create or replace function public.attach_verified_implementation_setup_sponsor_v1(
  p_checkout_session_id text,
  p_human_user_id uuid,
  p_verification_basis jsonb default '{}'::jsonb
) returns jsonb
language sql
security definer
set search_path = pg_catalog
as $$
  select atlas.attach_verified_implementation_setup_sponsor_v1(
    p_checkout_session_id,
    p_human_user_id,
    p_verification_basis
  );
$$;
revoke all on function public.attach_verified_implementation_setup_sponsor_v1(text,uuid,jsonb) from public, anon, authenticated;
grant execute on function public.attach_verified_implementation_setup_sponsor_v1(text,uuid,jsonb) to service_role;

-- Consequential transition from governed Establish records to canonical institutional truth.
create or replace function atlas.establish_implementation_organization_scope_self_api_v1(
  p_implementation_case_id uuid,
  p_institution_item_id uuid,
  p_ledger_scope_item_id uuid,
  p_ledger_entitlement_id uuid,
  p_organization_name text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_uid uuid := auth.uid();
  v_practitioner_participant_id uuid;
  v_org_id uuid := gen_random_uuid();
  v_org_name text := btrim(coalesce(p_organization_name,''));
  v_stable_base text;
  v_stable_key text;
  v_binding atlas.ledger_entitlement_bindings%rowtype;
  v_entitlement atlas.ledger_entitlements%rowtype;
  v_starting_label text;
begin
  if v_uid is null or not atlas.implementation_practitioner_authorized_self_v1() then
    raise exception 'Practitioner authority required.' using errcode='42501';
  end if;

  select cp.id into v_practitioner_participant_id
  from atlas.implementation_case_participants cp
  where cp.implementation_case_id=p_implementation_case_id
    and cp.relationship_kind='practitioner'
    and cp.active
    and cp.human_user_id=v_uid
  limit 1;

  if v_practitioner_participant_id is null then
    raise exception 'This implementation case is not assigned to the current practitioner.' using errcode='42501';
  end if;

  if not exists (
    select 1 from atlas.implementation_case_participants cp
    where cp.implementation_case_id=p_implementation_case_id
      and cp.relationship_kind='setup_sponsor' and cp.active
  ) then
    raise exception 'A verified setup sponsor is required before institutional scope can be established.' using errcode='23514';
  end if;

  if length(v_org_name) < 2 or length(v_org_name) > 160 then
    raise exception 'Organization name must be between 2 and 160 characters.' using errcode='22023';
  end if;

  if not exists (
    select 1 from atlas.implementation_establishment_items e
    where e.id=p_institution_item_id
      and e.implementation_case_id=p_implementation_case_id
      and e.category='institution'
      and e.status='established'
  ) then
    raise exception 'An established Institution record is required.' using errcode='23514';
  end if;

  if not exists (
    select 1 from atlas.implementation_establishment_items e
    where e.id=p_ledger_scope_item_id
      and e.implementation_case_id=p_implementation_case_id
      and e.category='ledger_scope'
      and e.status='established'
  ) then
    raise exception 'An established Ledger scope record is required.' using errcode='23514';
  end if;

  select le.* into v_entitlement
  from atlas.ledger_entitlements le
  where le.id=p_ledger_entitlement_id
    and le.implementation_case_id=p_implementation_case_id
  for update;

  if v_entitlement.id is null then
    raise exception 'Ledger entitlement not found for this implementation case.' using errcode='23503';
  end if;

  select b.* into v_binding
  from atlas.ledger_entitlement_bindings b
  where b.ledger_entitlement_id=v_entitlement.id and b.ended_at is null
  limit 1;

  if v_binding.id is not null then
    return jsonb_build_object(
      'ok',true,
      'alreadyBound',true,
      'organizationId',v_binding.organization_id,
      'ledgerEntitlementId',v_entitlement.id,
      'bindingId',v_binding.id,
      'bindingState',v_binding.state,
      'membershipCreated',false,
      'principalCreated',false
    );
  end if;

  if v_entitlement.state not in ('available','reserved') then
    raise exception 'Ledger entitlement is not available for initial binding.' using errcode='23514';
  end if;

  select p.starting_label into v_starting_label
  from atlas.implementation_cases c
  join atlas.implementation_purchases p on p.id=c.implementation_purchase_id
  where c.id=p_implementation_case_id;

  if v_starting_label is null then
    raise exception 'Implementation purchase is unavailable.' using errcode='23503';
  end if;

  v_stable_base := btrim(regexp_replace(lower(v_org_name), '[^a-z0-9]+', '_', 'g'), '_');
  if v_stable_base='' then v_stable_base:='organization'; end if;
  v_stable_key := v_stable_base;
  if exists(select 1 from atlas.organizations o where o.stable_key=v_stable_key) then
    v_stable_key := v_stable_base || '_' || substr(replace(v_org_id::text,'-',''),1,8);
  end if;

  insert into atlas.organizations(
    id,stable_key,name,status,metadata,onboarding_state,onboarding_started_at
  ) values (
    v_org_id,v_stable_key,v_org_name,'active',
    jsonb_build_object(
      'establishment_mode','practitioner_implementation',
      'implementation_case_id',p_implementation_case_id,
      'institution_establishment_item_id',p_institution_item_id,
      'ledger_scope_establishment_item_id',p_ledger_scope_item_id,
      'purchase_starting_label',v_starting_label,
      'membership_claimed',false,
      'principal_claimed',false
    ),
    'reconstructing',now()
  );

  insert into atlas.ledger_entitlement_bindings(
    implementation_case_id,ledger_entitlement_id,organization_id,organization_unit_id,
    bound_by_participant_id,state,binding_basis,metadata
  ) values (
    p_implementation_case_id,v_entitlement.id,v_org_id,null,
    v_practitioner_participant_id,'bound',
    jsonb_build_object(
      'source','establish_implementation_organization_scope_self_api_v1',
      'institutionEstablishmentItemId',p_institution_item_id,
      'ledgerScopeEstablishmentItemId',p_ledger_scope_item_id,
      'practitionerParticipantId',v_practitioner_participant_id
    ),
    jsonb_build_object('purchaseStartingLabel',v_starting_label)
  ) returning * into v_binding;

  update atlas.ledger_entitlements
  set state='bound', updated_at=now()
  where id=v_entitlement.id;

  update atlas.implementation_cases
  set metadata = metadata || jsonb_build_object(
      'institutionEstablishedAt',now(),
      'organizationId',v_org_id,
      'baselineLedgerBindingId',v_binding.id
    ),
    updated_at=now()
  where id=p_implementation_case_id;

  return jsonb_build_object(
    'ok',true,
    'alreadyBound',false,
    'organizationId',v_org_id,
    'organizationName',v_org_name,
    'organizationStableKey',v_stable_key,
    'ledgerEntitlementId',v_entitlement.id,
    'bindingId',v_binding.id,
    'bindingState',v_binding.state,
    'membershipCreated',false,
    'principalCreated',false
  );
end;
$$;

revoke all on function atlas.establish_implementation_organization_scope_self_api_v1(uuid,uuid,uuid,uuid,text) from public, anon, authenticated;
grant execute on function atlas.establish_implementation_organization_scope_self_api_v1(uuid,uuid,uuid,uuid,text) to authenticated, service_role;

create or replace function public.establish_implementation_organization_scope_self_api_v1(
  p_implementation_case_id uuid,
  p_institution_item_id uuid,
  p_ledger_scope_item_id uuid,
  p_ledger_entitlement_id uuid,
  p_organization_name text
) returns jsonb
language sql
security definer
set search_path = pg_catalog
as $$
  select atlas.establish_implementation_organization_scope_self_api_v1(
    p_implementation_case_id,
    p_institution_item_id,
    p_ledger_scope_item_id,
    p_ledger_entitlement_id,
    p_organization_name
  );
$$;
revoke all on function public.establish_implementation_organization_scope_self_api_v1(uuid,uuid,uuid,uuid,text) from public, anon;
grant execute on function public.establish_implementation_organization_scope_self_api_v1(uuid,uuid,uuid,uuid,text) to authenticated, service_role;

-- Return canonical scope names to the practitioner case shell once a Ledger is bound.
create or replace function atlas.implementation_case_self_api_v1(p_implementation_case_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare v_result jsonb;
begin
  if not atlas.implementation_practitioner_authorized_self_v1() then
    return jsonb_build_object('ok',false,'code','practitioner_authority_required');
  end if;

  select jsonb_build_object(
    'ok',true,
    'contractVersion','implementation_case_self_api_v1',
    'case',jsonb_build_object(
      'id',c.id,'state',c.state,'openedAt',c.opened_at,
      'purchase',jsonb_build_object(
        'id',p.id,'startingLabel',p.starting_label,'paymentOption',p.payment_option,
        'setupContractAmountCents',p.setup_contract_amount_cents,
        'monthlyLedgerUnitPriceCents',p.monthly_ledger_unit_price_cents,
        'purchasedAt',p.purchased_at,'purchaseState',p.purchase_state
      ),
      'participants',coalesce((select jsonb_agg(jsonb_build_object(
        'id',cp.id,'relationshipKind',cp.relationship_kind,'active',cp.active,
        'verifiedAt',cp.verified_at,'startedAt',cp.started_at,
        'isMe',cp.human_user_id=auth.uid()
      ) order by cp.started_at,cp.id) from atlas.implementation_case_participants cp where cp.implementation_case_id=c.id),'[]'::jsonb),
      'ledgerEntitlements',coalesce((select jsonb_agg(jsonb_build_object(
        'id',le.id,'number',le.entitlement_number,'state',le.state,
        'priceClass',le.price_class,'setupPriceCents',le.setup_price_cents,
        'monthlyPriceCents',le.monthly_price_cents,'recurringStartsAt',le.recurring_starts_at,
        'binding',(
          select jsonb_build_object(
            'id',b.id,'state',b.state,'organizationId',b.organization_id,
            'organizationName',o.name,
            'organizationUnitId',b.organization_unit_id,'organizationUnitName',ou.name,
            'boundAt',b.bound_at,'activatedAt',b.activated_at
          )
          from atlas.ledger_entitlement_bindings b
          join atlas.organizations o on o.id=b.organization_id
          left join atlas.organization_units ou on ou.id=b.organization_unit_id and ou.organization_id=b.organization_id
          where b.ledger_entitlement_id=le.id and b.ended_at is null limit 1
        )
      ) order by le.entitlement_number) from atlas.ledger_entitlements le where le.implementation_case_id=c.id),'[]'::jsonb)
    )
  ) into v_result
  from atlas.implementation_cases c
  join atlas.implementation_purchases p on p.id=c.implementation_purchase_id
  where c.id=p_implementation_case_id;

  return coalesce(v_result,jsonb_build_object('ok',false,'code','case_not_found'));
end;
$$;
