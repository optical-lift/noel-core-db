begin;

do $validation$
declare
  v_personal_settlement uuid;
  v_ledger_settlement uuid;
  v_personal jsonb;
  v_personal_replay jsonb;
  v_ledger jsonb;
  v_ledger_replay jsonb;
  v_begin jsonb;
  v_personal_purchase_id uuid;
  v_impl_purchase_id uuid;
  v_case_id uuid;
  v_entitlement_id uuid;
  v_before_principals integer;
  v_before_households integer;
  v_before_orgs integer;
  v_before_cases integer;
  v_before_entitlements integer;
begin
  if to_regclass('atlas.atlas_service_acquisition_compatibility_bindings') is null
     or to_regprocedure('atlas.record_atlas_service_settlement_service_v1(uuid,uuid,text,text,text,jsonb,timestamp with time zone,jsonb)') is null then
    raise exception 'Released Commercial Composition + acquisition compatibility prerequisites required.';
  end if;

  select count(*) into v_before_principals from atlas.principals;
  select count(*) into v_before_households from atlas.households;
  select count(*) into v_before_orgs from atlas.organizations;
  select count(*) into v_before_cases from atlas.implementation_cases;
  select count(*) into v_before_entitlements from atlas.ledger_entitlements;

  v_personal_settlement:=atlas.record_atlas_service_settlement_service_v1(
    'a6c10000-0000-4000-8000-000000000010'::uuid,
    'a6c10000-0000-4000-8000-000000000011'::uuid,
    'stripe','pi_forward_personal','USD',
    jsonb_build_array(
      jsonb_build_object(
        'itemId','a6c10000-0000-4000-8000-000000000013',
        'amountCents',3995
      )
    ),
    '2026-09-22T16:10:00Z'::timestamptz,
    '{"validation":"personal"}'::jsonb
  );

  if not exists(
    select 1
    from atlas.atlas_service_commercial_composition_items
    where id='a6c10000-0000-4000-8000-000000000013'::uuid
      and state='settled'
  ) or not exists(
    select 1
    from atlas.atlas_service_commercial_composition_items
    where id='a6c10000-0000-4000-8000-000000000014'::uuid
      and state='settlement_ready'
  ) then
    raise exception 'Personal setup Settlement incorrectly changed the deferred base recurring item.';
  end if;

  v_personal:=atlas.activate_atlas_service_activation_group_service_v1(
    'a6c10000-0000-4000-8000-000000000012'::uuid,
    v_personal_settlement,
    '{"providerSubscriptionId":"sub_forward_personal"}'::jsonb
  );

  v_personal_purchase_id:=(v_personal->>'personalAtlasPurchaseId')::uuid;

  if coalesce((v_personal->>'ok')::boolean,false)=false
     or coalesce((v_personal->>'alreadyActivated')::boolean,true)
     or v_personal_purchase_id is null then
    raise exception 'Personal forward activation returned invalid result: %',v_personal;
  end if;

  if (select count(*) from atlas.principals)<>v_before_principals
     or (select count(*) from atlas.households)<>v_before_households
     or (select count(*) from atlas.organizations)<>v_before_orgs then
    raise exception 'Personal commercial activation manufactured non-commercial identity/institution truth.';
  end if;

  if not exists(
    select 1
    from atlas.personal_atlas_purchases p
    where p.id=v_personal_purchase_id
      and p.provider='stripe'
      and p.provider_checkout_session_id is null
      and p.provider_subscription_id='sub_forward_personal'
      and p.purchaser_email='billing-personal@example.invalid'
      and p.claimed_by_user_id='a6c10000-0000-4000-8000-000000000001'::uuid
      and p.atlas_service_activation_group_id='a6c10000-0000-4000-8000-000000000012'::uuid
      and p.atlas_service_settlement_id=v_personal_settlement
      and p.metadata->>'billingEmailIsIdentityAuthority'='false'
  ) then
    raise exception 'Personal forward purchase lineage or payer/identity split is incorrect.';
  end if;

  if (
    select count(*)
    from atlas.atlas_service_commercial_composition_items
    where activation_group_id='a6c10000-0000-4000-8000-000000000012'::uuid
      and personal_atlas_purchase_id=v_personal_purchase_id
  )<>2 then
    raise exception 'Personal Activation Group items do not share the same downstream purchase lineage.';
  end if;

  v_personal_replay:=atlas.activate_atlas_service_activation_group_service_v1(
    'a6c10000-0000-4000-8000-000000000012'::uuid,
    v_personal_settlement,
    '{"providerSubscriptionId":"sub_forward_personal"}'::jsonb
  );

  if coalesce((v_personal_replay->>'alreadyActivated')::boolean,false)=false
     or (v_personal_replay->>'personalAtlasPurchaseId')::uuid<>v_personal_purchase_id
     or (select count(*) from atlas.personal_atlas_purchases where atlas_service_activation_group_id='a6c10000-0000-4000-8000-000000000012'::uuid)<>1 then
    raise exception 'Personal forward activation replay was not idempotent.';
  end if;

  begin
    insert into atlas.atlas_service_acquisition_compatibility_bindings(
      source_kind,personal_atlas_purchase_id,composition_id,metadata
    ) values(
      'personal_atlas_purchase',v_personal_purchase_id,
      'a6c10000-0000-4000-8000-000000000010'::uuid,
      '{"validation":"must_block"}'::jsonb
    );
    raise exception 'Forward Personal purchase was incorrectly accepted by compatibility import.';
  exception
    when check_violation then null;
  end;

  if exists(
    select 1
    from atlas.atlas_service_acquisition_compatibility_bindings
    where personal_atlas_purchase_id=v_personal_purchase_id
  ) then
    raise exception 'Compatibility binding survived forward-origin guard.';
  end if;

  perform set_config(
    'request.jwt.claim.sub',
    'a6c10000-0000-4000-8000-000000000001',
    true
  );

  v_begin:=atlas.begin_personal_atlas_self_api_v1(
    'Forward Atlas Human','America/Chicago'
  );

  if coalesce((v_begin->>'ok')::boolean,false)=false
     or (v_begin->>'purchaseId')::uuid<>v_personal_purchase_id
     or nullif(v_begin->>'principalId','') is null then
    raise exception 'Personal bootstrap could not use already-claimed forward purchase with different billing email: %',v_begin;
  end if;

  v_ledger_settlement:=atlas.record_atlas_service_settlement_service_v1(
    'a6c10000-0000-4000-8000-000000000020'::uuid,
    'a6c10000-0000-4000-8000-000000000021'::uuid,
    'stripe','pi_forward_ledger','USD',
    jsonb_build_array(
      jsonb_build_object(
        'itemId','a6c10000-0000-4000-8000-000000000023',
        'amountCents',300000
      )
    ),
    '2026-09-22T16:15:00Z'::timestamptz,
    '{"validation":"ledger"}'::jsonb
  );

  if not exists(
    select 1
    from atlas.atlas_service_commercial_composition_items
    where id='a6c10000-0000-4000-8000-000000000024'::uuid
      and state='settlement_ready'
  ) then
    raise exception 'Ledger setup Settlement incorrectly changed deferred recurring commercial state.';
  end if;

  v_ledger:=atlas.activate_atlas_service_activation_group_service_v1(
    'a6c10000-0000-4000-8000-000000000022'::uuid,
    v_ledger_settlement,
    '{
      "providerSubscriptionId":"sub_forward_ledger",
      "startingLabel":"Forward Activation Proof Institution",
      "recurringStartsAt":"2026-10-22T16:15:00Z"
    }'::jsonb
  );

  v_impl_purchase_id:=(v_ledger->>'implementationPurchaseId')::uuid;
  v_case_id:=(v_ledger->>'implementationCaseId')::uuid;
  v_entitlement_id:=(v_ledger->>'ledgerEntitlementId')::uuid;

  if coalesce((v_ledger->>'ok')::boolean,false)=false
     or coalesce((v_ledger->>'alreadyActivated')::boolean,true)
     or v_impl_purchase_id is null
     or v_case_id is null
     or v_entitlement_id is null then
    raise exception 'First-Ledger forward activation returned invalid result: %',v_ledger;
  end if;

  if (select count(*) from atlas.organizations)<>v_before_orgs
     or (select count(*) from atlas.implementation_case_participants where implementation_case_id=v_case_id)<>0
     or exists(select 1 from atlas.ledger_entitlement_bindings where ledger_entitlement_id=v_entitlement_id) then
    raise exception 'First-Ledger commercial activation manufactured institutional relationship/authority.';
  end if;

  if (select count(*) from atlas.implementation_cases)<>v_before_cases+1
     or (select count(*) from atlas.ledger_entitlements)<>v_before_entitlements+1 then
    raise exception 'First-Ledger activation did not create exactly one Case and one baseline Entitlement.';
  end if;

  if not exists(
    select 1
    from atlas.implementation_purchases p
    where p.id=v_impl_purchase_id
      and p.provider='stripe'
      and p.provider_checkout_session_id is null
      and p.provider_subscription_id='sub_forward_ledger'
      and p.offer_key='atlas_ledger_first_family'
      and p.payment_option='pay_in_full'
      and p.setup_contract_amount_cents=300000
      and p.monthly_ledger_unit_price_cents=40000
      and p.recurring_starts_at='2026-10-22T16:15:00Z'::timestamptz
      and p.atlas_service_activation_group_id='a6c10000-0000-4000-8000-000000000022'::uuid
      and p.atlas_service_settlement_id=v_ledger_settlement
  ) then
    raise exception 'First-Ledger Implementation Purchase lineage/amount snapshot is incorrect.';
  end if;

  if not exists(
    select 1
    from atlas.implementation_cases c
    where c.id=v_case_id
      and c.implementation_purchase_id=v_impl_purchase_id
      and c.state='awaiting_setup_human'
  ) then
    raise exception 'First-Ledger Implementation Case state is incorrect.';
  end if;

  if not exists(
    select 1
    from atlas.ledger_entitlements e
    where e.id=v_entitlement_id
      and e.implementation_case_id=v_case_id
      and e.source_purchase_id=v_impl_purchase_id
      and e.entitlement_number=1
      and e.price_class='baseline_first'
      and e.state='available'
      and e.setup_price_cents=300000
      and e.monthly_price_cents=40000
  ) then
    raise exception 'First-Ledger baseline Entitlement is incorrect.';
  end if;

  if (
    select count(*)
    from atlas.atlas_service_commercial_composition_items
    where activation_group_id='a6c10000-0000-4000-8000-000000000022'::uuid
      and implementation_purchase_id=v_impl_purchase_id
      and ledger_entitlement_id=v_entitlement_id
  )<>2 then
    raise exception 'First-Ledger Activation Group items do not share downstream lineage.';
  end if;

  v_ledger_replay:=atlas.activate_atlas_service_activation_group_service_v1(
    'a6c10000-0000-4000-8000-000000000022'::uuid,
    v_ledger_settlement,
    '{
      "providerSubscriptionId":"sub_forward_ledger",
      "startingLabel":"Forward Activation Proof Institution",
      "recurringStartsAt":"2026-10-22T16:15:00Z"
    }'::jsonb
  );

  if coalesce((v_ledger_replay->>'alreadyActivated')::boolean,false)=false
     or (v_ledger_replay->>'implementationPurchaseId')::uuid<>v_impl_purchase_id
     or (v_ledger_replay->>'implementationCaseId')::uuid<>v_case_id
     or (v_ledger_replay->>'ledgerEntitlementId')::uuid<>v_entitlement_id
     or (select count(*) from atlas.implementation_purchases where atlas_service_activation_group_id='a6c10000-0000-4000-8000-000000000022'::uuid)<>1 then
    raise exception 'First-Ledger forward activation replay was not idempotent.';
  end if;

  begin
    insert into atlas.atlas_service_acquisition_compatibility_bindings(
      source_kind,implementation_purchase_id,composition_id,metadata
    ) values(
      'implementation_purchase',v_impl_purchase_id,
      'a6c10000-0000-4000-8000-000000000020'::uuid,
      '{"validation":"must_block"}'::jsonb
    );
    raise exception 'Forward Implementation purchase was incorrectly accepted by compatibility import.';
  exception
    when check_violation then null;
  end;

  if has_function_privilege(
       'authenticated',
       'atlas.open_atlas_service_activation_group_service_v1(uuid,text,text,jsonb)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.bind_atlas_service_item_to_activation_group_service_v1(uuid,uuid)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.activate_atlas_service_activation_group_service_v1(uuid,uuid,jsonb)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'atlas.activate_atlas_service_activation_group_service_v1(uuid,uuid,jsonb)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'atlas.activate_atlas_service_activation_group_service_v1(uuid,uuid,jsonb)',
       'EXECUTE'
     ) then
    raise exception 'Settlement consequence activation privilege boundary is incorrect.';
  end if;

  if not exists(
    select 1
    from atlas.architecture_truth_authorities a
    where a.authority_key='atlas_service_settlement_consequence_activation'
      and a.authority_status='incomplete'
      and 'atlas.activate_atlas_service_activation_group_service_v1'=any(a.canonical_functions)
  ) then
    raise exception 'Settlement consequence activation architecture authority is missing or incorrect.';
  end if;

  if (
    select count(*)
    from atlas.authenticated_rpc_registry r
    where r.signature in (
      'atlas.open_atlas_service_activation_group_service_v1(uuid,text,text,jsonb)',
      'atlas.bind_atlas_service_item_to_activation_group_service_v1(uuid,uuid)',
      'atlas.activate_atlas_service_activation_group_service_v1(uuid,uuid,jsonb)'
    )
      and r.classification='service_internal'
      and r.authenticated_execute_expected=false
      and r.service_execute_expected=true
  )<>3 then
    raise exception 'Settlement consequence activation RPC registry contracts are missing or incorrect.';
  end if;
end;
$validation$;

rollback;
