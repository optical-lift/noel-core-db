begin;

do $validation$
declare
  v_composition_id uuid;
  v_base_item uuid;
  v_ledger_setup_item uuid;
  v_ledger_monthly_item uuid;
  v_withdraw_item uuid;
  v_payer uuid;
  v_other_payer uuid;
  v_result jsonb;
  v_position jsonb;
  v_settlement uuid;
  v_before_personal integer;
  v_before_implementation integer;
  v_before_entitlements integer;
  v_before_orders integer;
  v_after_personal integer;
  v_after_implementation integer;
  v_after_entitlements integer;
  v_after_orders integer;
  v_person_count integer;
  v_principal_count integer;
  v_def text;
begin
  select count(*) into v_before_personal from atlas.personal_atlas_purchases;
  select count(*) into v_before_implementation from atlas.implementation_purchases;
  select count(*) into v_before_entitlements from atlas.ledger_entitlements;
  select count(*) into v_before_orders from atlas.commercial_orders;

  -- Composition may begin after authentication but before Principal identity.
  v_composition_id:=atlas.open_atlas_service_commercial_composition_service_v1(
    'f4d00000-0000-4000-8000-000000000001'::uuid,
    null,
    null,
    'USD',
    now()+interval '7 days',
    '{"validationFixture":true}'::jsonb
  );

  select count(*) into v_person_count
  from atlas.people p
  join atlas.person_auth_credentials c on c.person_id=p.id
  where c.auth_user_id='f4d00000-0000-4000-8000-000000000001'::uuid
    and c.status='active';

  select count(*) into v_principal_count
  from atlas.principals
  where user_id='f4d00000-0000-4000-8000-000000000001'::uuid
    and status='active';

  if v_person_count<>0 or v_principal_count<>0 then
    raise exception 'Commercial Composition manufactured Person/Principal identity.';
  end if;

  -- Base Atlas and Ledger needs can coexist without product segmentation.
  v_base_item:=atlas.add_atlas_service_commercial_candidate_item_service_v1(
    v_composition_id,
    'atlas-base',
    'atlas_base_recurring',
    'recurring',
    700,
    1,
    'month',
    false,
    '{"source":"entry consent"}'::jsonb
  );

  v_ledger_setup_item:=atlas.add_atlas_service_commercial_candidate_item_service_v1(
    v_composition_id,
    'ci-ledger-setup',
    'ledger_implementation_first_family',
    'one_time',
    300000,
    1,
    null,
    true,
    '{"source":"institutional discovery"}'::jsonb
  );

  v_ledger_monthly_item:=atlas.add_atlas_service_commercial_candidate_item_service_v1(
    v_composition_id,
    'ci-ledger-monthly',
    'ledger_recurring',
    'recurring',
    40000,
    1,
    'month',
    true,
    '{"source":"institutional discovery"}'::jsonb
  );

  v_withdraw_item:=atlas.add_atlas_service_commercial_candidate_item_service_v1(
    v_composition_id,
    'declined-second-ledger',
    'ledger_implementation_additional_scope',
    'one_time',
    220000,
    1,
    null,
    true,
    '{"source":"discovered optional scope"}'::jsonb
  );

  v_position:=atlas.atlas_service_commercial_composition_position_v1(v_composition_id);

  if (v_position#>>'{counts,candidate}')::integer<>4
     or (v_position->>'settlementReadyOneTimeCents')::integer<>0 then
    raise exception 'Candidate commercial need became billable: %',v_position;
  end if;

  v_result:=atlas.propose_atlas_service_commercial_item_service_v1(
    v_withdraw_item,
    '{"reason":"optional second scope discovered"}'::jsonb
  );

  v_result:=atlas.withdraw_atlas_service_commercial_item_service_v1(
    v_withdraw_item,
    '{"decision":"not implementing this scope"}'::jsonb
  );

  if v_result->>'state'<>'withdrawn' then
    raise exception 'Declined commercial scope was not preserved as withdrawn: %',v_result;
  end if;

  v_result:=atlas.propose_atlas_service_commercial_item_service_v1(
    v_ledger_setup_item,
    '{"reason":"Atlas recognized institution-sized reality"}'::jsonb
  );

  if v_result->>'state'<>'proposed' then
    raise exception 'Candidate did not become proposed.';
  end if;

  begin
    perform atlas.elect_atlas_service_commercial_item_service_v1(
      v_ledger_setup_item,
      '{}'::jsonb
    );
    raise exception 'Explicit-election Ledger item elected without evidence.';
  exception when sqlstate '23514' then
    null;
  end;

  v_result:=atlas.elect_atlas_service_commercial_item_service_v1(
    v_ledger_setup_item,
    '{"authorizedBy":"fixture-commercial-approver","decision":"elect"}'::jsonb
  );

  if v_result->>'state'<>'elected' then
    raise exception 'Elected item should remain unready until payer accepts responsibility: %',v_result;
  end if;

  -- Billing identity remains billing identity only.
  v_payer:=atlas.ensure_atlas_service_payer_profile_service_v1(
    v_composition_id,
    'institution',
    'Camps International billing',
    'donate@campsinternational.org',
    null,
    null,
    'stripe',
    'cus_fixture_ci',
    '{"validationFixture":true}'::jsonb
  );

  select count(*) into v_person_count
  from atlas.people
  where lower(display_name) like '%camps international%';

  if v_person_count<>0 then
    raise exception 'Payer profile manufactured Person identity.';
  end if;

  v_other_payer:=atlas.ensure_atlas_service_payer_profile_service_v1(
    v_composition_id,
    'individual',
    'Other payer',
    'other@example.invalid',
    null,
    null,
    'stripe',
    'cus_fixture_other',
    '{"validationFixture":true}'::jsonb
  );

  v_result:=atlas.propose_atlas_service_item_payer_service_v1(
    v_ledger_setup_item,
    v_payer,
    '{"source":"billing-contact suggestion"}'::jsonb
  );

  if v_result->>'payerState'<>'proposed'
     or v_result->>'itemState'<>'elected' then
    raise exception 'Proposed payer altered item commercial state: %',v_result;
  end if;

  if (
    select state
    from atlas.atlas_service_commercial_composition_items
    where id=v_ledger_setup_item
  )<>'elected' then
    raise exception 'Proposed payer made elected item settlement-ready.';
  end if;

  begin
    perform atlas.accept_atlas_service_item_payer_service_v1(
      v_ledger_setup_item,
      v_payer,
      '{}'::jsonb
    );
    raise exception 'Payer responsibility accepted without evidence.';
  exception when sqlstate '23514' then
    null;
  end;

  v_result:=atlas.accept_atlas_service_item_payer_service_v1(
    v_ledger_setup_item,
    v_payer,
    '{"authorizedBy":"fixture-payer","decision":"accept responsibility"}'::jsonb
  );

  if v_result->>'itemState'<>'settlement_ready' then
    raise exception 'Elected item + accepted payer did not become settlement-ready: %',v_result;
  end if;

  -- Prepare base and recurring Ledger items for one batched settlement.
  perform atlas.propose_atlas_service_commercial_item_service_v1(
    v_base_item,
    '{"reason":"base Atlas entry consent"}'::jsonb
  );
  perform atlas.elect_atlas_service_commercial_item_service_v1(
    v_base_item,
    '{"entryConsent":true}'::jsonb
  );
  perform atlas.accept_atlas_service_item_payer_service_v1(
    v_base_item,
    v_payer,
    '{"authorizedBy":"fixture-payer","decision":"accept responsibility"}'::jsonb
  );

  perform atlas.propose_atlas_service_commercial_item_service_v1(
    v_ledger_monthly_item,
    '{"reason":"Ledger recurring disclosed"}'::jsonb
  );
  perform atlas.elect_atlas_service_commercial_item_service_v1(
    v_ledger_monthly_item,
    '{"authorizedBy":"fixture-commercial-approver","decision":"elect"}'::jsonb
  );
  perform atlas.accept_atlas_service_item_payer_service_v1(
    v_ledger_monthly_item,
    v_payer,
    '{"authorizedBy":"fixture-payer","decision":"accept responsibility"}'::jsonb
  );

  -- Wrong payer cannot settle a line.
  begin
    perform atlas.record_atlas_service_settlement_service_v1(
      v_composition_id,
      v_other_payer,
      'stripe',
      'pi_fixture_wrong_payer',
      'USD',
      jsonb_build_array(
        jsonb_build_object('itemId',v_ledger_setup_item,'amountCents',300000)
      ),
      now(),
      '{"validationFixture":true}'::jsonb
    );
    raise exception 'Settlement mixed payer responsibility.';
  exception when sqlstate '23514' then
    null;
  end;

  -- Candidate/proposed item cannot be settled.
  begin
    perform atlas.record_atlas_service_settlement_service_v1(
      v_composition_id,
      v_payer,
      'stripe',
      'pi_fixture_not_ready',
      'USD',
      jsonb_build_array(
        jsonb_build_object('itemId',gen_random_uuid(),'amountCents',1)
      ),
      now(),
      '{"validationFixture":true}'::jsonb
    );
    raise exception 'Settlement admitted non-ready item.';
  exception when sqlstate '23514' then
    null;
  end;

  -- One settlement batches independently meaningful items.
  v_settlement:=atlas.record_atlas_service_settlement_service_v1(
    v_composition_id,
    v_payer,
    'stripe',
    'pi_fixture_batch_1',
    'USD',
    jsonb_build_array(
      jsonb_build_object('itemId',v_base_item,'amountCents',700),
      jsonb_build_object('itemId',v_ledger_setup_item,'amountCents',300000),
      jsonb_build_object('itemId',v_ledger_monthly_item,'amountCents',40000)
    ),
    now(),
    '{"validationFixture":true}'::jsonb
  );

  if (
    select amount_cents from atlas.atlas_service_settlements
    where id=v_settlement
  )<>340700 then
    raise exception 'Batched Settlement total is incorrect.';
  end if;

  if (
    select count(*) from atlas.atlas_service_settlement_lines
    where settlement_id=v_settlement
  )<>3 then
    raise exception 'Batched Settlement did not preserve three independent lines.';
  end if;

  if (
    select state from atlas.atlas_service_commercial_composition_items
    where id=v_ledger_setup_item
  )<>'settled' then
    raise exception 'One-time Ledger setup did not become settled.';
  end if;

  if (
    select state from atlas.atlas_service_commercial_composition_items
    where id=v_base_item
  )<>'active'
     or (
       select state from atlas.atlas_service_commercial_composition_items
       where id=v_ledger_monthly_item
     )<>'active' then
    raise exception 'Recurring items did not become active after successful settlement.';
  end if;

  -- Provider settlement key is idempotent.
  if atlas.record_atlas_service_settlement_service_v1(
    v_composition_id,
    v_payer,
    'stripe',
    'pi_fixture_batch_1',
    'USD',
    jsonb_build_array(
      jsonb_build_object('itemId',v_base_item,'amountCents',700)
    ),
    now(),
    '{"duplicate":true}'::jsonb
  )<>v_settlement then
    raise exception 'Provider settlement idempotency failed.';
  end if;

  -- Composition/settlement never manufacture downstream purchase/entitlement/order truth.
  select count(*) into v_after_personal from atlas.personal_atlas_purchases;
  select count(*) into v_after_implementation from atlas.implementation_purchases;
  select count(*) into v_after_entitlements from atlas.ledger_entitlements;
  select count(*) into v_after_orders from atlas.commercial_orders;

  if v_after_personal<>v_before_personal
     or v_after_implementation<>v_before_implementation
     or v_after_entitlements<>v_before_entitlements
     or v_after_orders<>v_before_orders then
    raise exception 'Commercial Composition mutated downstream purchase/entitlement/order truth.';
  end if;

  -- Browser roles have no table or service-function authority.
  if has_table_privilege('authenticated','atlas.atlas_service_commercial_compositions','SELECT')
     or has_table_privilege('authenticated','atlas.atlas_service_commercial_composition_items','SELECT')
     or has_table_privilege('authenticated','atlas.atlas_service_payer_profiles','SELECT')
     or has_table_privilege('authenticated','atlas.atlas_service_settlements','SELECT')
     or has_function_privilege(
       'authenticated',
       'atlas.open_atlas_service_commercial_composition_service_v1(uuid,uuid,uuid,text,timestamp with time zone,jsonb)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'atlas.record_atlas_service_settlement_service_v1(uuid,uuid,text,text,text,jsonb,timestamp with time zone,jsonb)',
       'EXECUTE'
     ) then
    raise exception 'Commercial Composition service boundary leaked to browser roles.';
  end if;

  -- Read projection cannot mutate.
  select lower(pg_get_functiondef(
    'atlas.atlas_service_commercial_composition_position_v1(uuid)'::regprocedure
  )) into v_def;

  if v_def like '%insert into%'
     or v_def like '%update atlas.%'
     or v_def like '%delete from%'
     or v_def like '%execute %' then
    raise exception 'Commercial Composition position read contains mutation/dynamic execution.';
  end if;
end;
$validation$;

rollback;
