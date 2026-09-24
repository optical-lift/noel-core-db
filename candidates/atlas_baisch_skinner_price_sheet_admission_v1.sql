begin;

create or replace function atlas.baisch_skinner_price_sheet_admit_row_service_v1(
  p_connected_source_observation_id uuid,
  p_row_key text,
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
  v_row_key text:=nullif(btrim(coalesce(p_row_key,'')),'');
  v_observation_key text;
begin
  if p_connected_source_observation_id is null
     or v_row_key is null
     or p_supplier_relationship_id is null then
    raise exception 'Raw observation, rowKey, and supplier relationship are required.'
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
     or lower(v_source.provider_key)<>'baisch_skinner'
     or v_source.authorization_state<>'connected' then
    raise exception 'Baisch & Skinner admission requires a connected baisch_skinner source.'
      using errcode='55000';
  end if;

  if v_raw.provider_object_kind<>'published_price_sheet' then
    raise exception 'Baisch & Skinner price-sheet admission requires provider object kind published_price_sheet.'
      using errcode='23514';
  end if;

  if v_source.custodian_organization_id is null then
    raise exception 'Baisch & Skinner commercial admission requires organization custody.'
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

  v_interp:=atlas.baisch_skinner_price_sheet_row_interpret_v1(
    v_raw.payload,
    v_row_key,
    v_raw.observed_at
  );

  if coalesce((v_interp->'rowIdentity'->>'admissible')::boolean,false)=false then
    raise exception 'Baisch & Skinner row % is not admissible source-offer identity.',v_row_key
      using errcode='23514';
  end if;

  v_offering:=v_interp->'offeringDraft';
  v_observation:=v_interp->'observationDraft';

  if nullif(btrim(coalesce(v_offering->>'stableKey','')),'') is null
     or nullif(btrim(coalesce(v_offering->>'sourceLabel','')),'') is null
     or jsonb_typeof(v_observation->'priceAmount') is distinct from 'number' then
    raise exception 'Baisch & Skinner row cannot be admitted without stable identity, source label, and displayed price.'
      using errcode='23514';
  end if;

  v_offering_id:=atlas.ensure_external_supply_offering_service_v1(
    v_org_id,
    v_unit_id,
    p_supplier_relationship_id,
    v_offering->>'stableKey',
    v_offering->>'sourceItemKey',
    v_offering->>'sourceLabel',
    coalesce(nullif(v_offering->>'offeringKind',''),'item'),
    nullif(v_offering->>'sourceUnit',''),
    coalesce(v_offering->'specification','{}'::jsonb),
    coalesce(v_offering->'metadata','{}'::jsonb)||
      jsonb_build_object(
        'providerAdapter','baisch_skinner_price_sheet_provider_contract_v1',
        'connectedSourceId',v_source.id
      )
  );

  v_observation_key:=
    v_raw.provider_object_key||':'||
    v_row_key||':'||
    substr(v_raw.payload_sha256,1,16);

  v_observation_result:=atlas.record_external_supply_offer_observation_service_v1(
    v_offering_id,
    v_observation_key,
    v_raw.observed_at,
    (v_observation->>'effectiveFrom')::date,
    (v_observation->>'effectiveUntil')::date,
    (v_observation->>'priceAmount')::numeric,
    nullif(v_observation->>'currency',''),
    coalesce(nullif(v_observation->>'priceBasisState',''),'unknown'),
    case when jsonb_typeof(v_observation->'priceQuantity')='number'
      then (v_observation->>'priceQuantity')::numeric else null end,
    nullif(v_observation->>'priceUnit',''),
    case when jsonb_typeof(v_observation->'packQuantity')='number'
      then (v_observation->>'packQuantity')::numeric else null end,
    nullif(v_observation->>'packUnit',''),
    null,
    null,
    null,
    null,
    'unknown',
    coalesce(v_observation->'terms','{}'::jsonb),
    coalesce(v_observation->'sourceContext','{}'::jsonb)||
      jsonb_build_object(
        'providerObjectKey',v_raw.provider_object_key,
        'connectedSourceObservationId',v_raw.id,
        'rawObservedAt',v_raw.observed_at
      ),
    'supplier_price_list',
    v_raw.provider_object_key||'#'||v_row_key,
    null,
    v_raw.id,
    jsonb_build_object(
      'providerAdapter','baisch_skinner_price_sheet_provider_contract_v1',
      'providerFacts',v_interp->'providerFacts',
      'unresolvedSemantics',v_interp->'unresolvedSemantics',
      'sourcePreference',v_interp->'sourcePreference'
    )
  );

  return jsonb_build_object(
    'contractVersion','baisch_skinner_price_sheet_row_admission_v1',
    'connectedSourceObservationId',v_raw.id,
    'rowKey',v_row_key,
    'externalSupplyOfferingId',v_offering_id,
    'externalSupplyOfferObservationId',
      v_observation_result->'externalSupplyOfferObservationId',
    'created',v_observation_result->'created',
    'supplierRelationshipId',p_supplier_relationship_id,
    'organizationId',v_org_id,
    'organizationUnitId',v_unit_id,
    'interpretation',v_interp,
    'truthBoundary',jsonb_build_object(
      'rawDocumentPreserved',true,
      'supplierRelationshipExplicit',true,
      'unknownCurrencyPreserved',true,
      'unknownAvailabilityPreserved',true,
      'unknownFreightPreserved',true,
      'doesNotAuthorizePurchase',true,
      'doesNotCreateSpend',true,
      'doesNotCreateInventory',true,
      'doesNotCreateCustomerOffer',true
    )
  );
end;
$function$;


create or replace function atlas.baisch_skinner_price_sheet_admit_document_service_v1(
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
  v_row jsonb;
  v_interp jsonb;
  v_admitted jsonb:='[]'::jsonb;
  v_skipped jsonb:='[]'::jsonb;
  v_result jsonb;
begin
  select *
  into v_raw
  from atlas.connected_source_observations
  where id=p_connected_source_observation_id;

  if v_raw.id is null then
    raise exception 'Connected Source Observation not found.'
      using errcode='P0002';
  end if;

  if jsonb_typeof(v_raw.payload->'rows') is distinct from 'array' then
    raise exception 'Stored Baisch & Skinner normalized document does not contain rows.'
      using errcode='23514';
  end if;

  for v_row in
    select value from jsonb_array_elements(v_raw.payload->'rows')
  loop
    if nullif(btrim(coalesce(v_row->>'rowKey','')),'') is null then
      v_skipped:=v_skipped||jsonb_build_array(jsonb_build_object(
        'rowKey',null,
        'reason','row_key_missing'
      ));
      continue;
    end if;

    v_interp:=atlas.baisch_skinner_price_sheet_row_interpret_v1(
      v_raw.payload,
      v_row->>'rowKey',
      v_raw.observed_at
    );

    if coalesce((v_interp->'rowIdentity'->>'admissible')::boolean,false)=false then
      v_skipped:=v_skipped||jsonb_build_array(jsonb_build_object(
        'rowKey',v_row->>'rowKey',
        'rowKind',v_interp->'rowIdentity'->>'rowKind',
        'identityState',v_interp->'rowIdentity'->>'identityState',
        'reason','not_admissible_source_offer_row'
      ));
      continue;
    end if;

    v_result:=atlas.baisch_skinner_price_sheet_admit_row_service_v1(
      p_connected_source_observation_id,
      v_row->>'rowKey',
      p_supplier_relationship_id,
      p_organization_unit_id
    );

    v_admitted:=v_admitted||jsonb_build_array(v_result);
  end loop;

  return jsonb_build_object(
    'contractVersion','baisch_skinner_price_sheet_document_admission_v1',
    'connectedSourceObservationId',p_connected_source_observation_id,
    'admittedCount',jsonb_array_length(v_admitted),
    'skippedCount',jsonb_array_length(v_skipped),
    'admitted',v_admitted,
    'skipped',v_skipped,
    'truthBoundary',jsonb_build_object(
      'admitsSourceObservationsOnly',true,
      'skipsAmbiguousRows',true,
      'doesNotCompleteUnknownSemantics',true,
      'doesNotPurchase',true,
      'doesNotCreateSpend',true,
      'doesNotCreateInventory',true,
      'doesNotCreateCustomerOffer',true
    )
  );
end;
$function$;


revoke all on function atlas.baisch_skinner_price_sheet_admit_row_service_v1(uuid,text,uuid,uuid)
  from public,anon,authenticated;
grant execute on function atlas.baisch_skinner_price_sheet_admit_row_service_v1(uuid,text,uuid,uuid)
  to service_role;

revoke all on function atlas.baisch_skinner_price_sheet_admit_document_service_v1(uuid,uuid,uuid)
  from public,anon,authenticated;
grant execute on function atlas.baisch_skinner_price_sheet_admit_document_service_v1(uuid,uuid,uuid)
  to service_role;


insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,
  evidence,anonymous_execute_expected
) values
(
  'atlas.baisch_skinner_price_sheet_admit_row_service_v1(uuid,text,uuid,uuid)',
  'service_internal','provisional','active',
  false,true,true,0,1,
  '{"source":"atlas_baisch_skinner_price_sheet_admission_v1","purpose":"Admit one source-resolved row from a stored Baisch & Skinner normalized price sheet into External Supply Offer truth while preserving unresolved commercial facts.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.baisch_skinner_price_sheet_admit_document_service_v1(uuid,uuid,uuid)',
  'service_internal','provisional','active',
  false,true,true,0,1,
  '{"source":"atlas_baisch_skinner_price_sheet_admission_v1","purpose":"Batch-admit all source-resolved priced rows from one stored Baisch & Skinner normalized price sheet; ambiguous/header/composite rows are skipped and reported.","classificationRuleVersion":3}'::jsonb,
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
