begin;

create or replace function atlas.flowerbuyer_open_market_admit_observation_service_v1(
  p_connected_source_observation_id uuid,
  p_supplier_relationship_id uuid,
  p_organization_unit_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_raw atlas.connected_source_observations%rowtype;
  v_source atlas.connected_sources%rowtype;
  v_relationship atlas.external_relationships%rowtype;
  v_interp jsonb;
  v_offering jsonb;
  v_observation jsonb;
  v_offering_id uuid;
  v_observation_result jsonb;
  v_org_id uuid;
  v_unit_id uuid;
  v_observation_key text;
begin
  if p_connected_source_observation_id is null
     or p_supplier_relationship_id is null then
    raise exception 'Connected Source Observation and supplier relationship are required.'
      using errcode='22023';
  end if;

  select *
  into v_raw
  from atlas.connected_source_observations
  where id=p_connected_source_observation_id;

  if v_raw.id is null then
    raise exception 'Connected Source Observation not found.'
      using errcode='P0002';
  end if;

  select *
  into v_source
  from atlas.connected_sources
  where id=v_raw.connected_source_id;

  if v_source.id is null
     or lower(v_source.provider_key)<>'flowerbuyer'
     or v_source.authorization_state<>'connected' then
    raise exception 'Flowerbuyer admission requires a connected Flowerbuyer source.'
      using errcode='55000';
  end if;

  if v_raw.provider_object_kind<>'market_listing' then
    raise exception 'Flowerbuyer Open Market admission requires provider object kind market_listing.'
      using errcode='23514';
  end if;

  if v_source.custodian_organization_id is null then
    raise exception 'Flowerbuyer commercial admission requires organization custody.'
      using errcode='23514';
  end if;

  v_org_id:=v_source.custodian_organization_id;
  v_unit_id:=coalesce(p_organization_unit_id,v_source.custodian_organization_unit_id);

  if v_unit_id is not null and not exists(
    select 1
    from atlas.organization_units u
    where u.id=v_unit_id
      and u.organization_id=v_org_id
      and u.status='active'
  ) then
    raise exception 'Organization unit is not an active unit of the source organization.'
      using errcode='23514';
  end if;

  select *
  into v_relationship
  from atlas.external_relationships
  where id=p_supplier_relationship_id;

  if v_relationship.id is null
     or v_relationship.organization_id<>v_org_id
     or v_relationship.relationship_state<>'active' then
    raise exception 'Supplier relationship must be active and belong to the source organization.'
      using errcode='23514';
  end if;

  if not exists(
    select 1
    from atlas.external_relationship_roles rr
    where rr.external_relationship_id=p_supplier_relationship_id
      and rr.role_key='supplier'
      and rr.role_state='active'
  ) then
    raise exception 'Relationship does not carry an active supplier role.'
      using errcode='23514';
  end if;

  v_interp:=atlas.flowerbuyer_open_market_record_interpret_v1(
    v_raw.payload,
    v_raw.observed_at
  );

  v_offering:=v_interp->'offeringDraft';
  v_observation:=v_interp->'observationDraft';

  if nullif(btrim(coalesce(v_offering->>'stableKey','')),'') is null
     or nullif(btrim(coalesce(v_offering->>'sourceLabel','')),'') is null
     or nullif(btrim(coalesce(v_offering->>'sourceUnit','')),'') is null then
    raise exception 'Flowerbuyer observation cannot be admitted until product identity, label, and source unit are resolved.'
      using errcode='23514';
  end if;

  if jsonb_typeof(v_observation->'priceAmount') is distinct from 'number'
     or nullif(btrim(coalesce(v_observation->>'currency','')),'') is null
     or v_observation->>'priceBasisState'<>'source_explicit'
     or jsonb_typeof(v_observation->'priceQuantity') is distinct from 'number'
     or nullif(btrim(coalesce(v_observation->>'priceUnit','')),'') is null then
    raise exception 'Flowerbuyer observation cannot be admitted until account price and price unit are source-explicit.'
      using errcode='23514';
  end if;

  v_offering_id:=atlas.ensure_external_supply_offering_service_v1(
    v_org_id,
    v_unit_id,
    p_supplier_relationship_id,
    v_offering->>'stableKey',
    v_offering->>'sourceItemKey',
    v_offering->>'sourceLabel',
    coalesce(nullif(v_offering->>'offeringKind',''),'cut_flower'),
    v_offering->>'sourceUnit',
    coalesce(v_offering->'specification','{}'::jsonb),
    coalesce(v_offering->'metadata','{}'::jsonb)||
      jsonb_build_object(
        'providerAdapter','flowerbuyer_open_market_provider_contract_v1',
        'connectedSourceId',v_source.id
      )
  );

  v_observation_key:=
    (v_interp->'rawRecordIdentity'->>'providerObjectKey')||':'||
    substr(v_raw.payload_sha256,1,16);

  v_observation_result:=atlas.record_external_supply_offer_observation_service_v1(
    v_offering_id,
    v_observation_key,
    v_raw.observed_at,
    null,
    null,
    (v_observation->>'priceAmount')::numeric,
    v_observation->>'currency',
    v_observation->>'priceBasisState',
    (v_observation->>'priceQuantity')::numeric,
    v_observation->>'priceUnit',
    case when jsonb_typeof(v_observation->'packQuantity')='number'
      then (v_observation->>'packQuantity')::numeric else null end,
    v_observation->>'packUnit',
    case when jsonb_typeof(v_observation->'minimumOrderQuantity')='number'
      then (v_observation->>'minimumOrderQuantity')::numeric else null end,
    v_observation->>'minimumOrderUnit',
    null,
    null,
    coalesce(nullif(v_observation->>'availabilityState',''),'unknown'),
    coalesce(v_observation->'terms','{}'::jsonb),
    coalesce(v_observation->'sourceContext','{}'::jsonb)||
      jsonb_build_object(
        'providerKey','flowerbuyer',
        'providerObjectKey',v_raw.provider_object_key,
        'connectedSourceObservationId',v_raw.id,
        'rawObservedAt',v_raw.observed_at
      ),
    'supplier_portal',
    v_raw.provider_object_key,
    null,
    v_raw.id,
    jsonb_build_object(
      'providerAdapter','flowerbuyer_open_market_provider_contract_v1',
      'providerFacts',v_interp->'providerFacts',
      'unresolvedSemantics',v_interp->'unresolvedSemantics',
      'sourcePreference',v_interp->'sourcePreference',
      'transport',coalesce(v_raw.provenance->>'captureMethod','unresolved')
    )
  );

  return jsonb_build_object(
    'contractVersion','flowerbuyer_open_market_admission_v1',
    'connectedSourceObservationId',v_raw.id,
    'externalSupplyOfferingId',v_offering_id,
    'externalSupplyOfferObservationId',
      v_observation_result->'externalSupplyOfferObservationId',
    'created',v_observation_result->'created',
    'supplierRelationshipId',p_supplier_relationship_id,
    'organizationId',v_org_id,
    'organizationUnitId',v_unit_id,
    'interpretation',v_interp,
    'truthBoundary',jsonb_build_object(
      'rawObservationPreserved',true,
      'supplierRelationshipExplicit',true,
      'doesNotInferGrowOrigin',true,
      'doesNotCreateSourcePreferenceTier',true,
      'doesNotAuthorizePurchase',true,
      'doesNotCreateSpend',true,
      'doesNotCreateInventory',true,
      'doesNotCreateCustomerOffer',true
    )
  );
end;
$function$;


revoke all on function atlas.flowerbuyer_open_market_admit_observation_service_v1(uuid,uuid,uuid)
  from public,anon,authenticated;
grant execute on function atlas.flowerbuyer_open_market_admit_observation_service_v1(uuid,uuid,uuid)
  to service_role;


insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,
  evidence,anonymous_execute_expected
) values (
  'atlas.flowerbuyer_open_market_admit_observation_service_v1(uuid,uuid,uuid)',
  'service_internal','provisional','active',
  false,true,true,0,1,
  '{"source":"atlas_flowerbuyer_open_market_admission_v1","purpose":"Explicitly admit one stored raw Flowerbuyer Open Market observation into External Supply Offer truth using an operator-resolved supplier relationship; does not purchase or create Spend.","classificationRuleVersion":3}'::jsonb,
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
