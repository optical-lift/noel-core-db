begin;

do $validation$
declare
  v_personal jsonb;
  v_personal_replay jsonb;
  v_implementation jsonb;
  v_implementation_replay jsonb;
  v_personal_comp uuid;
  v_implementation_comp uuid;
  v_personal_setup uuid;
  v_personal_base uuid;
  v_impl_setup uuid;
  v_impl_recurring uuid;
  v_before_personal integer;
  v_before_implementation integer;
  v_before_cases integer;
  v_before_entitlements integer;
  v_before_principals integer;
  v_before_households integer;
  v_before_organizations integer;
  v_before_settlements integer;
  v_before_settlement_lines integer;
begin
  if to_regclass('atlas.atlas_service_commercial_compositions') is null
     or to_regprocedure('atlas.atlas_service_commercial_price_policy_v1(text,date)') is null
     or to_regprocedure('atlas.accept_atlas_service_item_payer_service_v1(uuid,uuid,jsonb)') is null then
    raise exception 'Production-live Commercial Composition, price policy, and payer acceptance prerequisites are required.';
  end if;

  select count(*) into v_before_personal from atlas.personal_atlas_purchases;
  select count(*) into v_before_implementation from atlas.implementation_purchases;
  select count(*) into v_before_cases from atlas.implementation_cases;
  select count(*) into v_before_entitlements from atlas.ledger_entitlements;
  select count(*) into v_before_principals from atlas.principals;
  select count(*) into v_before_households from atlas.households;
  select count(*) into v_before_organizations from atlas.organizations;
  select count(*) into v_before_settlements from atlas.atlas_service_settlements;
  select count(*) into v_before_settlement_lines from atlas.atlas_service_settlement_lines;

  v_personal:=atlas.reconcile_personal_atlas_purchase_to_composition_service_v1(
    'a5c10000-0000-4000-8000-000000000011'::uuid,
    '{"validationRun":"first"}'::jsonb
  );

  if coalesce((v_personal->>'ok')::boolean,false)=false
     or coalesce((v_personal->>'alreadyReconciled')::boolean,true)
     or v_personal->>'sourceKind'<>'personal_atlas_purchase'
     or coalesce((v_personal->>'syntheticSettlementCreated')::boolean,true) then
    raise exception 'Personal purchase reconciliation returned an invalid first result: %',v_personal;
  end if;

  v_personal_comp:=(v_personal->>'compositionId')::uuid;
  v_personal_setup:=(v_personal->>'setupItemId')::uuid;
  v_personal_base:=(v_personal->>'baseItemId')::uuid;

  if not exists(
    select 1
    from atlas.atlas_service_acquisition_compatibility_bindings b
    where b.source_kind='personal_atlas_purchase'
      and b.personal_atlas_purchase_id='a5c10000-0000-4000-8000-000000000011'::uuid
      and b.composition_id=v_personal_comp
      and b.implementation_purchase_id is null
  ) then
    raise exception 'Personal acquisition compatibility binding is missing.';
  end if;

  if not exists(
    select 1
    from atlas.atlas_service_commercial_composition_items i
    where i.id=v_personal_setup
      and i.composition_id=v_personal_comp
      and i.item_kind='atlas_initial_setup'
      and i.state='settled'
      and i.unit_amount_cents=3995
      and i.personal_atlas_purchase_id='a5c10000-0000-4000-8000-000000000011'::uuid
      and i.metadata->>'syntheticSettlementCreated'='false'
  ) then
    raise exception 'Personal setup compatibility item is incorrect.';
  end if;

  if not exists(
    select 1
    from atlas.atlas_service_commercial_composition_items i
    where i.id=v_personal_base
      and i.composition_id=v_personal_comp
      and i.item_kind='atlas_base_recurring'
      and i.state='active'
      and i.unit_amount_cents=700
      and i.billing_interval='month'
      and i.personal_atlas_purchase_id='a5c10000-0000-4000-8000-000000000011'::uuid
      and i.metadata->>'syntheticSettlementCreated'='false'
  ) then
    raise exception 'Personal base compatibility item is incorrect.';
  end if;

  if (
    select count(*)
    from atlas.atlas_service_item_payer_responsibilities r
    join atlas.atlas_service_payer_profiles p on p.id=r.payer_profile_id
    where r.composition_item_id in (v_personal_setup,v_personal_base)
      and r.state='accepted'
      and lower(p.billing_email)='acquisition-compat-personal@example.invalid'
  )<>2 then
    raise exception 'Existing Personal purchase did not preserve accepted payer responsibility for both purchased lines.';
  end if;

  if exists(
    select 1
    from atlas.atlas_service_payer_profiles p
    where p.composition_id=v_personal_comp
      and p.canonical_person_id is not null
  ) then
    raise exception 'Billing email was silently promoted into Canonical Person identity.';
  end if;

  v_personal_replay:=atlas.reconcile_personal_atlas_purchase_to_composition_service_v1(
    'a5c10000-0000-4000-8000-000000000011'::uuid,
    '{"validationRun":"replay"}'::jsonb
  );

  if coalesce((v_personal_replay->>'alreadyReconciled')::boolean,false)=false
     or (v_personal_replay->>'compositionId')::uuid<>v_personal_comp
     or (v_personal_replay->>'setupItemId')::uuid<>v_personal_setup
     or (v_personal_replay->>'baseItemId')::uuid<>v_personal_base then
    raise exception 'Personal compatibility replay was not idempotent: %',v_personal_replay;
  end if;

  if (
    select count(*)
    from atlas.atlas_service_commercial_composition_items
    where composition_id=v_personal_comp
  )<>2 then
    raise exception 'Personal compatibility replay duplicated Composition Items.';
  end if;

  v_implementation:=atlas.reconcile_implementation_purchase_to_composition_service_v1(
    'a5c10000-0000-4000-8000-000000000021'::uuid,
    '{"validationRun":"first"}'::jsonb
  );

  if coalesce((v_implementation->>'ok')::boolean,false)=false
     or coalesce((v_implementation->>'alreadyReconciled')::boolean,true)
     or v_implementation->>'sourceKind'<>'implementation_purchase'
     or coalesce((v_implementation->>'payerReconstructed')::boolean,true)
     or coalesce((v_implementation->>'syntheticSettlementCreated')::boolean,true) then
    raise exception 'Implementation purchase reconciliation returned an invalid first result: %',v_implementation;
  end if;

  v_implementation_comp:=(v_implementation->>'compositionId')::uuid;
  v_impl_setup:=(v_implementation->>'setupItemId')::uuid;
  v_impl_recurring:=(v_implementation->>'recurringItemId')::uuid;

  if not exists(
    select 1
    from atlas.atlas_service_acquisition_compatibility_bindings b
    where b.source_kind='implementation_purchase'
      and b.implementation_purchase_id='a5c10000-0000-4000-8000-000000000021'::uuid
      and b.composition_id=v_implementation_comp
      and b.personal_atlas_purchase_id is null
  ) then
    raise exception 'Implementation acquisition compatibility binding is missing.';
  end if;

  if not exists(
    select 1
    from atlas.atlas_service_commercial_composition_items i
    where i.id=v_impl_setup
      and i.composition_id=v_implementation_comp
      and i.item_kind='ledger_implementation_first_family'
      and i.state='active'
      and i.unit_amount_cents=300000
      and i.implementation_purchase_id='a5c10000-0000-4000-8000-000000000021'::uuid
      and i.ledger_entitlement_id='a5c10000-0000-4000-8000-000000000023'::uuid
      and i.metadata->>'historicalSettlementDetailReconstructed'='false'
  ) then
    raise exception 'Implementation setup compatibility item is incorrect.';
  end if;

  if not exists(
    select 1
    from atlas.atlas_service_commercial_composition_items i
    where i.id=v_impl_recurring
      and i.composition_id=v_implementation_comp
      and i.item_kind='ledger_recurring'
      and i.state='active'
      and i.unit_amount_cents=40000
      and i.billing_interval='month'
      and i.implementation_purchase_id='a5c10000-0000-4000-8000-000000000021'::uuid
      and i.ledger_entitlement_id='a5c10000-0000-4000-8000-000000000023'::uuid
      and i.metadata->>'payerReconstructed'='false'
  ) then
    raise exception 'Implementation recurring compatibility item is incorrect.';
  end if;

  if exists(
    select 1
    from atlas.atlas_service_payer_profiles p
    where p.composition_id=v_implementation_comp
  ) then
    raise exception 'Implementation compatibility adapter guessed a payer not carried by canonical purchase evidence.';
  end if;

  v_implementation_replay:=atlas.reconcile_implementation_purchase_to_composition_service_v1(
    'a5c10000-0000-4000-8000-000000000021'::uuid,
    '{"validationRun":"replay"}'::jsonb
  );

  if coalesce((v_implementation_replay->>'alreadyReconciled')::boolean,false)=false
     or (v_implementation_replay->>'compositionId')::uuid<>v_implementation_comp
     or (v_implementation_replay->>'setupItemId')::uuid<>v_impl_setup
     or (v_implementation_replay->>'recurringItemId')::uuid<>v_impl_recurring then
    raise exception 'Implementation compatibility replay was not idempotent: %',v_implementation_replay;
  end if;

  if (
    select count(*)
    from atlas.atlas_service_commercial_composition_items
    where composition_id=v_implementation_comp
  )<>2 then
    raise exception 'Implementation compatibility replay duplicated Composition Items.';
  end if;

  if (select count(*) from atlas.personal_atlas_purchases)<>v_before_personal
     or (select count(*) from atlas.implementation_purchases)<>v_before_implementation
     or (select count(*) from atlas.implementation_cases)<>v_before_cases
     or (select count(*) from atlas.ledger_entitlements)<>v_before_entitlements
     or (select count(*) from atlas.principals)<>v_before_principals
     or (select count(*) from atlas.households)<>v_before_households
     or (select count(*) from atlas.organizations)<>v_before_organizations then
    raise exception 'Compatibility reconciliation mutated downstream acquisition or institutional truth.';
  end if;

  if (select count(*) from atlas.atlas_service_settlements)<>v_before_settlements
     or (select count(*) from atlas.atlas_service_settlement_lines)<>v_before_settlement_lines then
    raise exception 'Compatibility reconciliation fabricated a Commercial Composition Settlement.';
  end if;

  if has_table_privilege(
       'authenticated',
       'atlas.atlas_service_acquisition_compatibility_bindings',
       'SELECT'
     )
     or has_table_privilege(
       'anon',
       'atlas.atlas_service_acquisition_compatibility_bindings',
       'SELECT'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.reconcile_personal_atlas_purchase_to_composition_service_v1(uuid,jsonb)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.reconcile_implementation_purchase_to_composition_service_v1(uuid,jsonb)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'atlas.reconcile_personal_atlas_purchase_to_composition_service_v1(uuid,jsonb)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'atlas.reconcile_implementation_purchase_to_composition_service_v1(uuid,jsonb)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'atlas.reconcile_personal_atlas_purchase_to_composition_service_v1(uuid,jsonb)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'atlas.reconcile_implementation_purchase_to_composition_service_v1(uuid,jsonb)',
       'EXECUTE'
     ) then
    raise exception 'Acquisition compatibility privilege boundary is incorrect.';
  end if;

  if not exists(
    select 1
    from atlas.architecture_truth_authorities a
    where a.authority_key='atlas_service_acquisition_compatibility'
      and a.authority_status='transitional'
      and 'atlas.reconcile_personal_atlas_purchase_to_composition_service_v1'=any(a.canonical_functions)
      and 'atlas.reconcile_implementation_purchase_to_composition_service_v1'=any(a.canonical_functions)
  ) then
    raise exception 'Acquisition compatibility architecture authority is missing or incorrect.';
  end if;

  if (
    select count(*)
    from atlas.authenticated_rpc_registry r
    where r.signature in (
      'atlas.reconcile_personal_atlas_purchase_to_composition_service_v1(uuid,jsonb)',
      'atlas.reconcile_implementation_purchase_to_composition_service_v1(uuid,jsonb)'
    )
      and r.classification='service_internal'
      and r.authenticated_execute_expected=false
      and r.service_execute_expected=true
  )<>2 then
    raise exception 'Acquisition compatibility RPC registry contracts are missing or incorrect.';
  end if;
end;
$validation$;

rollback;
