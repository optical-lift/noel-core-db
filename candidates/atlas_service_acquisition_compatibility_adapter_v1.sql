begin;

create table if not exists atlas.atlas_service_acquisition_compatibility_bindings (
  id uuid primary key default gen_random_uuid(),
  source_kind text not null
    check (source_kind in ('personal_atlas_purchase','implementation_purchase')),
  personal_atlas_purchase_id uuid
    references atlas.personal_atlas_purchases(id) on delete restrict,
  implementation_purchase_id uuid
    references atlas.implementation_purchases(id) on delete restrict,
  composition_id uuid not null
    references atlas.atlas_service_commercial_compositions(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (source_kind='personal_atlas_purchase'
      and personal_atlas_purchase_id is not null
      and implementation_purchase_id is null)
    or
    (source_kind='implementation_purchase'
      and implementation_purchase_id is not null
      and personal_atlas_purchase_id is null)
  )
);

create unique index if not exists atlas_service_acquisition_compat_personal_uq
  on atlas.atlas_service_acquisition_compatibility_bindings(personal_atlas_purchase_id)
  where personal_atlas_purchase_id is not null;

create unique index if not exists atlas_service_acquisition_compat_implementation_uq
  on atlas.atlas_service_acquisition_compatibility_bindings(implementation_purchase_id)
  where implementation_purchase_id is not null;

create unique index if not exists atlas_service_acquisition_compat_composition_uq
  on atlas.atlas_service_acquisition_compatibility_bindings(composition_id);

alter table atlas.atlas_service_acquisition_compatibility_bindings enable row level security;
revoke all on table atlas.atlas_service_acquisition_compatibility_bindings
  from public,anon,authenticated,service_role;


create or replace function atlas.reconcile_personal_atlas_purchase_to_composition_service_v1(
  p_purchase_id uuid,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_purchase atlas.personal_atlas_purchases%rowtype;
  v_binding atlas.atlas_service_acquisition_compatibility_bindings%rowtype;
  v_composition_id uuid;
  v_setup_item_id uuid;
  v_base_item_id uuid;
  v_payer_id uuid;
  v_person_id uuid;
  v_setup_policy jsonb;
  v_base_policy jsonb;
  v_currency text;
begin
  if p_purchase_id is null then
    raise exception 'Personal Atlas purchase id required.' using errcode='22023';
  end if;

  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Compatibility reconciliation metadata must be a JSON object.'
      using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'atlas-service-personal-purchase:'||p_purchase_id::text,0
  ));

  select * into v_binding
  from atlas.atlas_service_acquisition_compatibility_bindings b
  where b.personal_atlas_purchase_id=p_purchase_id
  limit 1;

  if v_binding.id is not null then
    select id into v_setup_item_id
    from atlas.atlas_service_commercial_composition_items
    where composition_id=v_binding.composition_id
      and item_key='legacy-personal-setup'
    limit 1;

    select id into v_base_item_id
    from atlas.atlas_service_commercial_composition_items
    where composition_id=v_binding.composition_id
      and item_key='legacy-personal-base'
    limit 1;

    return jsonb_build_object(
      'ok',true,
      'alreadyReconciled',true,
      'sourceKind',v_binding.source_kind,
      'purchaseId',p_purchase_id,
      'compositionId',v_binding.composition_id,
      'setupItemId',v_setup_item_id,
      'baseItemId',v_base_item_id
    );
  end if;

  select * into v_purchase
  from atlas.personal_atlas_purchases p
  where p.id=p_purchase_id
  for update;

  if v_purchase.id is null then
    raise exception 'Personal Atlas purchase not found.' using errcode='P0002';
  end if;

  if v_purchase.purchase_state<>'active' then
    raise exception 'Only an active Personal Atlas purchase may be reconciled into active Commercial Composition compatibility.'
      using errcode='23514';
  end if;

  if v_purchase.claimed_by_user_id is null then
    raise exception 'Personal Atlas purchase must already be claimed by an authenticated human before compatibility reconciliation.'
      using errcode='23514';
  end if;

  v_setup_policy:=atlas.atlas_service_commercial_price_policy_v1(
    'atlas_initial_setup',v_purchase.purchased_at::date
  );
  v_base_policy:=atlas.atlas_service_commercial_price_policy_v1(
    'atlas_base_recurring',v_purchase.purchased_at::date
  );

  if v_setup_policy->>'currency' is distinct from v_base_policy->>'currency' then
    raise exception 'Personal Atlas compatibility policies must resolve to one currency.'
      using errcode='23514';
  end if;

  v_currency:=v_setup_policy->>'currency';

  select c.person_id into v_person_id
  from atlas.person_auth_credentials c
  join atlas.people p on p.id=c.person_id
  where c.auth_user_id=v_purchase.claimed_by_user_id
    and c.status='active'
    and p.status='active'
  limit 1;

  v_composition_id:=atlas.open_atlas_service_commercial_composition_service_v1(
    v_purchase.claimed_by_user_id,
    v_purchase.claimed_principal_id,
    null,
    v_currency,
    null,
    jsonb_build_object(
      'source','personal_atlas_purchase_compatibility_reconciliation',
      'personalAtlasPurchaseId',v_purchase.id,
      'provider',v_purchase.provider,
      'providerCheckoutSessionId',v_purchase.provider_checkout_session_id,
      'providerSubscriptionId',v_purchase.provider_subscription_id,
      'historicalPurchaseAuthorityRemains','atlas.personal_atlas_purchases',
      'syntheticSettlementCreated',false
    ) || p_metadata
  );

  insert into atlas.atlas_service_acquisition_compatibility_bindings(
    source_kind,personal_atlas_purchase_id,composition_id,metadata
  ) values(
    'personal_atlas_purchase',v_purchase.id,v_composition_id,
    jsonb_build_object(
      'source','reconcile_personal_atlas_purchase_to_composition_service_v1',
      'authorityDirection','existing_purchase_to_composition',
      'syntheticSettlementCreated',false
    ) || p_metadata
  )
  returning * into v_binding;

  insert into atlas.atlas_service_commercial_composition_items(
    composition_id,item_key,item_kind,charge_kind,state,currency,
    unit_amount_cents,quantity,billing_interval,requires_explicit_election,
    elected_at,election_evidence,personal_atlas_purchase_id,metadata
  ) values(
    v_composition_id,'legacy-personal-setup','atlas_initial_setup','one_time',
    'elected',v_currency,
    (v_setup_policy->>'unitAmountCents')::integer,1,null,false,
    v_purchase.purchased_at,
    jsonb_build_object(
      'basis','existing_personal_atlas_purchase',
      'purchaseId',v_purchase.id,
      'providerCheckoutSessionId',v_purchase.provider_checkout_session_id
    ),
    v_purchase.id,
    jsonb_build_object(
      'compatibilityBindingId',v_binding.id,
      'pricePolicyId',v_setup_policy->>'pricePolicyId',
      'priceKey',v_setup_policy->>'priceKey',
      'historicalStateImported',true,
      'syntheticSettlementCreated',false
    )
  )
  returning id into v_setup_item_id;

  insert into atlas.atlas_service_commercial_composition_items(
    composition_id,item_key,item_kind,charge_kind,state,currency,
    unit_amount_cents,quantity,billing_interval,requires_explicit_election,
    elected_at,election_evidence,personal_atlas_purchase_id,metadata
  ) values(
    v_composition_id,'legacy-personal-base','atlas_base_recurring','recurring',
    'elected',v_currency,
    (v_base_policy->>'unitAmountCents')::integer,1,
    v_base_policy->>'billingInterval',false,
    v_purchase.purchased_at,
    jsonb_build_object(
      'basis','existing_personal_atlas_purchase',
      'purchaseId',v_purchase.id,
      'providerSubscriptionId',v_purchase.provider_subscription_id
    ),
    v_purchase.id,
    jsonb_build_object(
      'compatibilityBindingId',v_binding.id,
      'pricePolicyId',v_base_policy->>'pricePolicyId',
      'priceKey',v_base_policy->>'priceKey',
      'historicalStateImported',true,
      'syntheticSettlementCreated',false
    )
  )
  returning id into v_base_item_id;

  v_payer_id:=atlas.ensure_atlas_service_payer_profile_service_v1(
    v_composition_id,
    'individual',
    null,
    v_purchase.purchaser_email,
    v_person_id,
    null,
    v_purchase.provider,
    null,
    jsonb_build_object(
      'source','existing_personal_atlas_purchase',
      'personalAtlasPurchaseId',v_purchase.id,
      'billingEmailIsIdentityAuthority',false
    )
  );

  perform atlas.accept_atlas_service_item_payer_service_v1(
    v_setup_item_id,
    v_payer_id,
    jsonb_build_object(
      'basis','existing_completed_personal_purchase',
      'purchaseId',v_purchase.id,
      'providerCheckoutSessionId',v_purchase.provider_checkout_session_id
    )
  );

  perform atlas.accept_atlas_service_item_payer_service_v1(
    v_base_item_id,
    v_payer_id,
    jsonb_build_object(
      'basis','existing_completed_personal_purchase',
      'purchaseId',v_purchase.id,
      'providerSubscriptionId',v_purchase.provider_subscription_id
    )
  );

  update atlas.atlas_service_commercial_composition_items
  set state='settled',
      updated_at=now()
  where id=v_setup_item_id;

  update atlas.atlas_service_commercial_composition_items
  set state='active',
      updated_at=now()
  where id=v_base_item_id;

  return jsonb_build_object(
    'ok',true,
    'alreadyReconciled',false,
    'sourceKind','personal_atlas_purchase',
    'purchaseId',v_purchase.id,
    'compositionId',v_composition_id,
    'setupItemId',v_setup_item_id,
    'baseItemId',v_base_item_id,
    'payerProfileId',v_payer_id,
    'syntheticSettlementCreated',false
  );
end;
$function$;

revoke all on function atlas.reconcile_personal_atlas_purchase_to_composition_service_v1(uuid,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.reconcile_personal_atlas_purchase_to_composition_service_v1(uuid,jsonb)
  to service_role;


create or replace function atlas.reconcile_implementation_purchase_to_composition_service_v1(
  p_purchase_id uuid,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_purchase atlas.implementation_purchases%rowtype;
  v_case atlas.implementation_cases%rowtype;
  v_entitlement atlas.ledger_entitlements%rowtype;
  v_binding atlas.atlas_service_acquisition_compatibility_bindings%rowtype;
  v_composition_id uuid;
  v_setup_item_id uuid;
  v_recurring_item_id uuid;
begin
  if p_purchase_id is null then
    raise exception 'Implementation purchase id required.' using errcode='22023';
  end if;

  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Compatibility reconciliation metadata must be a JSON object.'
      using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'atlas-service-implementation-purchase:'||p_purchase_id::text,0
  ));

  select * into v_binding
  from atlas.atlas_service_acquisition_compatibility_bindings b
  where b.implementation_purchase_id=p_purchase_id
  limit 1;

  if v_binding.id is not null then
    select id into v_setup_item_id
    from atlas.atlas_service_commercial_composition_items
    where composition_id=v_binding.composition_id
      and item_key='legacy-ledger-implementation'
    limit 1;

    select id into v_recurring_item_id
    from atlas.atlas_service_commercial_composition_items
    where composition_id=v_binding.composition_id
      and item_key='legacy-ledger-recurring'
    limit 1;

    return jsonb_build_object(
      'ok',true,
      'alreadyReconciled',true,
      'sourceKind',v_binding.source_kind,
      'purchaseId',p_purchase_id,
      'compositionId',v_binding.composition_id,
      'setupItemId',v_setup_item_id,
      'recurringItemId',v_recurring_item_id
    );
  end if;

  select * into v_purchase
  from atlas.implementation_purchases p
  where p.id=p_purchase_id
  for update;

  if v_purchase.id is null then
    raise exception 'Implementation purchase not found.' using errcode='P0002';
  end if;

  if v_purchase.purchase_state<>'active' then
    raise exception 'Only an active Implementation purchase may be reconciled into active Commercial Composition compatibility.'
      using errcode='23514';
  end if;

  select * into v_case
  from atlas.implementation_cases c
  where c.implementation_purchase_id=v_purchase.id;

  if v_case.id is null then
    raise exception 'Implementation purchase has no Implementation Case.'
      using errcode='23514';
  end if;

  select * into v_entitlement
  from atlas.ledger_entitlements e
  where e.implementation_case_id=v_case.id
    and e.source_purchase_id=v_purchase.id
    and e.entitlement_number=1
    and e.price_class='baseline_first'
  limit 1;

  if v_entitlement.id is null then
    raise exception 'Implementation purchase has no baseline Ledger Entitlement.'
      using errcode='23514';
  end if;

  v_composition_id:=atlas.open_atlas_service_commercial_composition_service_v1(
    null,
    null,
    v_case.id,
    upper(v_purchase.currency),
    null,
    jsonb_build_object(
      'source','implementation_purchase_compatibility_reconciliation',
      'implementationPurchaseId',v_purchase.id,
      'implementationCaseId',v_case.id,
      'ledgerEntitlementId',v_entitlement.id,
      'historicalPurchaseAuthorityRemains','atlas.implementation_purchases',
      'payerReconstructed',false,
      'syntheticSettlementCreated',false
    ) || p_metadata
  );

  insert into atlas.atlas_service_acquisition_compatibility_bindings(
    source_kind,implementation_purchase_id,composition_id,metadata
  ) values(
    'implementation_purchase',v_purchase.id,v_composition_id,
    jsonb_build_object(
      'source','reconcile_implementation_purchase_to_composition_service_v1',
      'authorityDirection','existing_purchase_to_composition',
      'payerReconstructed',false,
      'syntheticSettlementCreated',false
    ) || p_metadata
  )
  returning * into v_binding;

  insert into atlas.atlas_service_commercial_composition_items(
    composition_id,item_key,item_kind,charge_kind,state,currency,
    unit_amount_cents,quantity,billing_interval,requires_explicit_election,
    elected_at,election_evidence,implementation_purchase_id,
    ledger_entitlement_id,metadata
  ) values(
    v_composition_id,'legacy-ledger-implementation',
    'ledger_implementation_first_family','one_time','active',
    upper(v_purchase.currency),
    v_purchase.setup_contract_amount_cents,1,null,true,
    v_purchase.purchased_at,
    jsonb_build_object(
      'basis','existing_implementation_purchase',
      'purchaseId',v_purchase.id,
      'providerCheckoutSessionId',v_purchase.provider_checkout_session_id,
      'paymentOption',v_purchase.payment_option
    ),
    v_purchase.id,v_entitlement.id,
    jsonb_build_object(
      'compatibilityBindingId',v_binding.id,
      'historicalStateImported',true,
      'historicalSettlementDetailReconstructed',false,
      'syntheticSettlementCreated',false
    )
  )
  returning id into v_setup_item_id;

  insert into atlas.atlas_service_commercial_composition_items(
    composition_id,item_key,item_kind,charge_kind,state,currency,
    unit_amount_cents,quantity,billing_interval,requires_explicit_election,
    elected_at,election_evidence,implementation_purchase_id,
    ledger_entitlement_id,metadata
  ) values(
    v_composition_id,'legacy-ledger-recurring',
    'ledger_recurring','recurring','active',
    upper(v_purchase.currency),
    v_purchase.monthly_ledger_unit_price_cents,1,'month',true,
    v_purchase.purchased_at,
    jsonb_build_object(
      'basis','existing_implementation_purchase',
      'purchaseId',v_purchase.id,
      'providerSubscriptionId',v_purchase.provider_subscription_id
    ),
    v_purchase.id,v_entitlement.id,
    jsonb_build_object(
      'compatibilityBindingId',v_binding.id,
      'recurringStartsAt',v_purchase.recurring_starts_at,
      'historicalStateImported',true,
      'payerReconstructed',false,
      'syntheticSettlementCreated',false
    )
  )
  returning id into v_recurring_item_id;

  return jsonb_build_object(
    'ok',true,
    'alreadyReconciled',false,
    'sourceKind','implementation_purchase',
    'purchaseId',v_purchase.id,
    'implementationCaseId',v_case.id,
    'ledgerEntitlementId',v_entitlement.id,
    'compositionId',v_composition_id,
    'setupItemId',v_setup_item_id,
    'recurringItemId',v_recurring_item_id,
    'payerReconstructed',false,
    'syntheticSettlementCreated',false
  );
end;
$function$;

revoke all on function atlas.reconcile_implementation_purchase_to_composition_service_v1(uuid,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.reconcile_implementation_purchase_to_composition_service_v1(uuid,jsonb)
  to service_role;


insert into atlas.architecture_truth_authorities(
  authority_key,domain_key,truth_question,authority_owner,authority_status,
  canonical_relations,canonical_functions,supporting_relations,
  consumer_surfaces,known_competitors,source_custody,rationale,updated_at
) values (
  'atlas_service_acquisition_compatibility',
  'atlas_service_commerce',
  'How is already-authoritative legacy Atlas acquisition truth represented inside Commercial Composition during acquisition convergence?',
  'atlas_service_acquisition_compatibility_bindings',
  'transitional',
  array['atlas.atlas_service_acquisition_compatibility_bindings'],
  array[
    'atlas.reconcile_personal_atlas_purchase_to_composition_service_v1',
    'atlas.reconcile_implementation_purchase_to_composition_service_v1'
  ],
  array[
    'atlas.personal_atlas_purchases',
    'atlas.implementation_purchases',
    'atlas.implementation_cases',
    'atlas.ledger_entitlements',
    'atlas.atlas_service_commercial_compositions',
    'atlas.atlas_service_commercial_composition_items',
    'atlas.atlas_service_payer_profiles',
    'atlas.atlas_service_item_payer_responsibilities'
  ],
  array[]::text[],
  array[]::text[],
  'Legacy purchase records remain authoritative for purchases already made. Compatibility reconciliation is one-way purchase-to-composition lineage and creates no provider charge or synthetic Settlement.',
  'Provides an idempotent bridge while Personal and Organization checkout paths are cut over to Commercial Composition-first acquisition.',
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
  'atlas.reconcile_personal_atlas_purchase_to_composition_service_v1(uuid,jsonb)',
  'service_internal','verified','active',
  false,true,true,0,1,
  jsonb_build_object(
    'source','atlas_service_acquisition_compatibility_adapter_v1',
    'purpose','Idempotently reflect an already-active claimed Personal Atlas purchase into Commercial Composition without creating another purchase or settlement.',
    'truthBoundary','Existing purchase remains authority; billing email does not establish Person identity; no synthetic Settlement.',
    'classificationRuleVersion',3
  ),
  false
),
(
  'atlas.reconcile_implementation_purchase_to_composition_service_v1(uuid,jsonb)',
  'service_internal','verified','active',
  false,true,true,0,1,
  jsonb_build_object(
    'source','atlas_service_acquisition_compatibility_adapter_v1',
    'purpose','Idempotently reflect an already-active Implementation purchase and baseline Ledger entitlement into Commercial Composition without reconstructing payer identity.',
    'truthBoundary','Existing purchase/entitlement remain authority; setup sponsor is not payer; no synthetic Settlement.',
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
