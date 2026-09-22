begin;

do $validation$
declare
  v_policy jsonb;
  v_before_items integer;
  v_before_purchases integer;
  v_before_entitlements integer;
  v_before_settlements integer;
begin
  select count(*) into v_before_items
  from atlas.atlas_service_commercial_composition_items;

  select count(*) into v_before_purchases
  from atlas.personal_atlas_purchases;

  select count(*) into v_before_entitlements
  from atlas.ledger_entitlements;

  select count(*) into v_before_settlements
  from atlas.atlas_service_settlements;

  v_policy:=atlas.atlas_service_commercial_price_policy_v1(
    'atlas_initial_setup','2026-09-22'
  );
  if (v_policy->>'unitAmountCents')::integer<>3995
     or v_policy->>'chargeKind'<>'one_time'
     or v_policy->>'policyStatus'<>'transitional'
     or coalesce((v_policy->>'requiresExplicitElection')::boolean,true) then
    raise exception 'Personal setup compatibility policy is incorrect: %',v_policy;
  end if;

  v_policy:=atlas.atlas_service_commercial_price_policy_v1(
    'atlas_base_recurring','2026-09-22'
  );
  if (v_policy->>'unitAmountCents')::integer<>700
     or v_policy->>'billingInterval'<>'month'
     or coalesce((v_policy->>'requiresExplicitElection')::boolean,true) then
    raise exception 'Base Atlas monthly policy is incorrect: %',v_policy;
  end if;

  v_policy:=atlas.atlas_service_commercial_price_policy_v1(
    'ledger_implementation_first_family','2026-09-22'
  );
  if (v_policy->>'unitAmountCents')::integer<>300000
     or coalesce((v_policy->>'requiresExplicitElection')::boolean,false)=false then
    raise exception 'First Ledger setup policy is incorrect: %',v_policy;
  end if;

  v_policy:=atlas.atlas_service_commercial_price_policy_v1(
    'ledger_implementation_additional_scope','2026-09-22'
  );
  if (v_policy->>'unitAmountCents')::integer<>220000 then
    raise exception 'Additional Ledger setup policy is incorrect: %',v_policy;
  end if;

  v_policy:=atlas.atlas_service_commercial_price_policy_v1(
    'ledger_recurring','2026-09-22'
  );
  if (v_policy->>'unitAmountCents')::integer<>40000
     or v_policy->>'billingInterval'<>'month' then
    raise exception 'Ledger recurring policy is incorrect: %',v_policy;
  end if;

  v_policy:=atlas.atlas_service_commercial_price_policy_v1(
    'ledger_connection_recurring','2026-09-22'
  );
  if (v_policy->>'unitAmountCents')::integer<>700
     or v_policy->>'billingInterval'<>'month' then
    raise exception 'Ledger Connection recurring policy is incorrect: %',v_policy;
  end if;

  begin
    perform atlas.atlas_service_commercial_price_policy_v1(
      'not_a_real_item_kind','2026-09-22'
    );
    raise exception 'Unknown Atlas service price policy resolved.';
  exception when sqlstate '23514' then
    null;
  end;

  -- Overlapping active/transitional policy must fail.
  begin
    insert into atlas.atlas_service_commercial_price_policies(
      price_key,item_kind,charge_kind,unit_amount_cents,currency,billing_interval,
      requires_explicit_election,policy_status,effective_from,source_note
    ) values(
      'fixture-overlap',
      'atlas_base_recurring','recurring',701,'USD','month',
      false,'active','2026-09-15','fixture overlap'
    );
    raise exception 'Overlapping Atlas service price policy was admitted.';
  exception when sqlstate '23514' then
    null;
  end;

  if has_table_privilege(
       'authenticated',
       'atlas.atlas_service_commercial_price_policies',
       'SELECT'
     )
     or has_table_privilege(
       'anon',
       'atlas.atlas_service_commercial_price_policies',
       'SELECT'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.atlas_service_commercial_price_policy_v1(text,date)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'atlas.atlas_service_commercial_price_policy_v1(text,date)',
       'EXECUTE'
     ) then
    raise exception 'Atlas service price-policy privilege boundary is incorrect.';
  end if;

  if (select count(*) from atlas.atlas_service_commercial_composition_items)<>v_before_items
     or (select count(*) from atlas.personal_atlas_purchases)<>v_before_purchases
     or (select count(*) from atlas.ledger_entitlements)<>v_before_entitlements
     or (select count(*) from atlas.atlas_service_settlements)<>v_before_settlements then
    raise exception 'Price-policy read created commercial/purchase/entitlement truth.';
  end if;
end;
$validation$;

rollback;
