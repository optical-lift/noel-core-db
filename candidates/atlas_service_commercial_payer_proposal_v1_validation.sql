begin;

do $validation$
declare
  v_composition_id uuid;
  v_item_id uuid;
  v_payer_id uuid;
  v_result jsonb;
  v_before_personal integer;
  v_before_implementation integer;
  v_before_entitlements integer;
  v_before_orders integer;
  v_after_personal integer;
  v_after_implementation integer;
  v_after_entitlements integer;
  v_after_orders integer;
begin
  if to_regclass('atlas.atlas_service_commercial_compositions') is null
     or to_regprocedure('atlas.accept_atlas_service_item_payer_service_v1(uuid,uuid,jsonb)') is null then
    raise exception 'Live parent Commercial Composition v1 is required before payer-proposal migration.';
  end if;

  select count(*) into v_before_personal from atlas.personal_atlas_purchases;
  select count(*) into v_before_implementation from atlas.implementation_purchases;
  select count(*) into v_before_entitlements from atlas.ledger_entitlements;
  select count(*) into v_before_orders from atlas.commercial_orders;

  v_composition_id:=atlas.open_atlas_service_commercial_composition_service_v1(
    'f4e00000-0000-4000-8000-000000000001'::uuid,
    null,
    null,
    'USD',
    now()+interval '7 days',
    '{"validationFixture":true}'::jsonb
  );

  v_item_id:=atlas.add_atlas_service_commercial_candidate_item_service_v1(
    v_composition_id,
    'institution-ledger-setup',
    'ledger_implementation_first_family',
    'one_time',
    300000,
    1,
    null,
    true,
    '{"source":"institutional discovery"}'::jsonb
  );

  perform atlas.propose_atlas_service_commercial_item_service_v1(
    v_item_id,
    '{"reason":"institutional complexity"}'::jsonb
  );

  perform atlas.elect_atlas_service_commercial_item_service_v1(
    v_item_id,
    '{"authorizedBy":"fixture-commercial-approver","decision":"elect"}'::jsonb
  );

  v_payer_id:=atlas.ensure_atlas_service_payer_profile_service_v1(
    v_composition_id,
    'institution',
    'Institution billing',
    'billing@example.invalid',
    null,
    null,
    'stripe',
    'cus_fixture_payer_proposal',
    '{"validationFixture":true}'::jsonb
  );

  v_result:=atlas.propose_atlas_service_item_payer_service_v1(
    v_item_id,
    v_payer_id,
    '{"source":"billing-contact suggestion"}'::jsonb
  );

  if v_result->>'payerState'<>'proposed'
     or v_result->>'itemState'<>'elected' then
    raise exception 'Payer proposal altered commercial item state: %',v_result;
  end if;

  if not exists(
    select 1
    from atlas.atlas_service_item_payer_responsibilities r
    where r.composition_item_id=v_item_id
      and r.payer_profile_id=v_payer_id
      and r.state='proposed'
      and r.metadata#>>'{proposalEvidence,source}'='billing-contact suggestion'
  ) then
    raise exception 'Payer proposal relation/evidence was not preserved.';
  end if;

  if exists(
    select 1
    from atlas.atlas_service_item_payer_responsibilities r
    where r.composition_item_id=v_item_id
      and r.state='accepted'
  ) then
    raise exception 'Payer proposal silently created accepted financial responsibility.';
  end if;

  if (
    select state
    from atlas.atlas_service_commercial_composition_items
    where id=v_item_id
  )<>'elected' then
    raise exception 'Payer proposal made elected item settlement-ready.';
  end if;

  v_result:=atlas.accept_atlas_service_item_payer_service_v1(
    v_item_id,
    v_payer_id,
    '{"authorizedBy":"fixture-payer","decision":"accept responsibility"}'::jsonb
  );

  if v_result->>'itemState'<>'settlement_ready' then
    raise exception 'Accepted payer did not move elected item to settlement-ready: %',v_result;
  end if;

  select count(*) into v_after_personal from atlas.personal_atlas_purchases;
  select count(*) into v_after_implementation from atlas.implementation_purchases;
  select count(*) into v_after_entitlements from atlas.ledger_entitlements;
  select count(*) into v_after_orders from atlas.commercial_orders;

  if v_after_personal<>v_before_personal
     or v_after_implementation<>v_before_implementation
     or v_after_entitlements<>v_before_entitlements
     or v_after_orders<>v_before_orders then
    raise exception 'Payer proposal/acceptance mutated downstream purchase, entitlement, or Order truth.';
  end if;

  if has_function_privilege(
       'authenticated',
       'atlas.propose_atlas_service_item_payer_service_v1(uuid,uuid,jsonb)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'atlas.propose_atlas_service_item_payer_service_v1(uuid,uuid,jsonb)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'atlas.propose_atlas_service_item_payer_service_v1(uuid,uuid,jsonb)',
       'EXECUTE'
     ) then
    raise exception 'Payer proposal RPC privilege boundary is incorrect.';
  end if;

  if not exists(
    select 1
    from atlas.architecture_truth_authorities a
    where a.authority_key='atlas_service_payer_responsibility'
      and 'atlas.propose_atlas_service_item_payer_service_v1'=any(a.canonical_functions)
  ) then
    raise exception 'Payer proposal function is missing from architecture truth authority.';
  end if;

  if not exists(
    select 1
    from atlas.authenticated_rpc_registry r
    where r.signature='atlas.propose_atlas_service_item_payer_service_v1(uuid,uuid,jsonb)'
      and r.classification='service_internal'
      and r.authenticated_execute_expected=false
      and r.service_execute_expected=true
  ) then
    raise exception 'Payer proposal RPC registry contract is missing or incorrect.';
  end if;
end;
$validation$;

rollback;
