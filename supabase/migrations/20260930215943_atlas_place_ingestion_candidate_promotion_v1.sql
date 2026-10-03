-- ATLAS_CONTACT_SET_PAIRED_GEOGRAPHY_V1: promote a source-backed Place candidate through governed geography identity.

create or replace function atlas.promote_place_ingestion_candidate_to_reality_service_v1(
  p_candidate_id uuid,
  p_promotion_basis jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer
set search_path to ''
as $function$
declare
  v_candidate local_intel.entity_ingestion_candidates%rowtype;
  v_ingestion_source local_intel.ingestion_sources%rowtype;
  v_source local_intel.sources%rowtype;
  v_attempt atlas.contact_set_acquisition_attempts%rowtype;
  v_fields jsonb;
  v_reference jsonb;
  v_attempt_id uuid;
  v_name text;
  v_state text;
  v_country text;
  v_area_type text;
  v_place_kind text;
  v_identity_namespace text;
  v_identity_key text;
  v_stable_key text;
  v_lat numeric;
  v_lon numeric;
  v_precision text;
  v_area_id uuid;
  v_area_count integer;
  v_existing_area local_intel.geographic_areas%rowtype;
  v_identity_resolution jsonb;
  v_entity_id uuid;
  v_entity reality.entities%rowtype;
  v_profile reality.place_profiles%rowtype;
  v_admission jsonb;
  v_source_key_receipt jsonb;
  v_local_id_receipt jsonb;
  v_local_stable_receipt jsonb;
  v_created_area boolean:=false;
begin
  if p_candidate_id is null then raise exception 'Place ingestion candidate id is required.' using errcode='22023'; end if;
  if p_promotion_basis is null or jsonb_typeof(p_promotion_basis)<>'object' then raise exception 'Promotion basis must be a JSON object.' using errcode='22023'; end if;

  select * into v_candidate
  from local_intel.entity_ingestion_candidates
  where id=p_candidate_id
  for update;
  if v_candidate.id is null then raise exception 'Place ingestion candidate not found.' using errcode='P0002'; end if;
  if v_candidate.proposed_entity_type<>'place' then raise exception 'Only a Place ingestion candidate may use this promotion membrane.' using errcode='23514'; end if;
  if v_candidate.review_state='promoted' then
    return jsonb_build_object(
      'contractVersion','atlas_place_ingestion_candidate_promotion_v1','state','existing',
      'candidateId',v_candidate.id,
      'geographicAreaId',v_candidate.metadata->>'promotedGeographicAreaId',
      'entityId',v_candidate.metadata->>'canonicalPlaceEntityId'
    );
  end if;
  if v_candidate.review_state not in ('pending','needs_review') then
    raise exception 'Place ingestion candidate is not promotable in state %',v_candidate.review_state using errcode='23514';
  end if;

  begin v_attempt_id:=nullif(v_candidate.metadata->>'atlasAcquisitionAttemptId','')::uuid;
  exception when invalid_text_representation then raise exception 'Candidate acquisition lineage is invalid.' using errcode='23514'; end;
  if v_attempt_id is null then raise exception 'Place candidate must preserve an Atlas acquisition attempt.' using errcode='23514'; end if;

  select * into v_attempt
  from atlas.contact_set_acquisition_attempts
  where id=v_attempt_id;
  if v_attempt.id is null or v_attempt.gap->>'gapKind'<>'geography_resolution_gap' then
    raise exception 'Place candidate must originate from a geography_resolution_gap.' using errcode='23514';
  end if;
  if v_attempt.local_context_id<>v_candidate.local_context_id then
    raise exception 'Place candidate local context does not match acquisition attempt.' using errcode='23514';
  end if;

  select * into v_ingestion_source
  from local_intel.ingestion_sources where id=v_candidate.ingestion_source_id;
  if v_ingestion_source.id is null then raise exception 'Candidate ingestion source not found.' using errcode='P0002'; end if;
  select * into v_source from local_intel.sources where id=v_ingestion_source.source_id;
  if v_source.id is null then raise exception 'Candidate source not found.' using errcode='P0002'; end if;
  if v_source.source_kind<>'geography_reference' then
    raise exception 'Place promotion requires source_kind=geography_reference.' using errcode='23514';
  end if;

  v_fields:=coalesce(case when jsonb_typeof(v_candidate.metadata->'fields')='object' then v_candidate.metadata->'fields' end,'{}'::jsonb);
  v_reference:=v_attempt.gap->'placeReference';
  if v_reference is null or jsonb_typeof(v_reference)<>'object' then
    raise exception 'Geography acquisition attempt is missing the persisted Place reference.' using errcode='23514';
  end if;

  v_name:=coalesce(nullif(btrim(v_fields->>'name'),''),nullif(btrim(v_candidate.proposed_name),''));
  v_state:=nullif(upper(btrim(coalesce(v_fields->>'state',v_fields->>'administrativeHint',''))),'');
  v_country:=nullif(upper(btrim(v_fields->>'countryCode')),'');
  v_area_type:=coalesce(nullif(lower(btrim(v_fields->>'areaType')),''),'locality');
  v_identity_namespace:=nullif(lower(btrim(v_fields->>'sourceIdentityNamespace')),'');
  v_identity_key:=nullif(btrim(v_fields->>'sourceIdentityKey'),'');
  v_precision:=coalesce(nullif(btrim(v_fields->>'centroidPrecision'),''),'source_reported');

  if v_name is null or v_country is null or v_country !~ '^[A-Z]{2}$' then
    raise exception 'Place candidate requires name and two-letter countryCode.' using errcode='22023';
  end if;
  if v_identity_namespace is null or v_identity_key is null then
    raise exception 'Place candidate requires sourceIdentityNamespace and sourceIdentityKey before promotion.' using errcode='23514';
  end if;
  if v_area_type not in ('locality','region') then
    raise exception 'Place candidate promotion v1 supports locality or region only.' using errcode='23514';
  end if;
  v_place_kind:=v_area_type;
  if v_area_type='locality' and v_state is null then
    raise exception 'Locality candidate requires state/administrativeHint.' using errcode='23514';
  end if;

  if nullif(v_reference->>'identityNamespace','') is not null or nullif(v_reference->>'identityKey','') is not null then
    if lower(btrim(v_reference->>'identityNamespace')) is distinct from v_identity_namespace
       or btrim(v_reference->>'identityKey') is distinct from v_identity_key then
      raise exception 'Acquired Place identity does not match the persisted source identity reference.' using errcode='23514';
    end if;
  elsif nullif(v_reference->>'name','') is not null then
    if lower(btrim(v_reference->>'name'))<>lower(v_name)
       or upper(btrim(coalesce(v_reference->>'administrativeHint',''))) is distinct from coalesce(v_state,'')
       or upper(btrim(coalesce(v_reference->>'countryCode',''))) is distinct from v_country
       or lower(btrim(coalesce(v_reference->>'placeKind','locality'))) is distinct from v_place_kind then
      raise exception 'Acquired Place candidate does not exactly match the persisted named Place reference.' using errcode='23514';
    end if;
  else
    raise exception 'Unsupported unresolved Place reference mode for research promotion.' using errcode='23514';
  end if;

  begin
    if nullif(v_fields->>'centroidLatitude','') is not null then v_lat:=(v_fields->>'centroidLatitude')::numeric; end if;
    if nullif(v_fields->>'centroidLongitude','') is not null then v_lon:=(v_fields->>'centroidLongitude')::numeric; end if;
  exception when invalid_text_representation then
    raise exception 'Place centroid coordinates must be numeric when supplied.' using errcode='22023';
  end;
  if (v_lat is null) <> (v_lon is null) then raise exception 'Place centroid latitude and longitude must be supplied together.' using errcode='22023'; end if;
  if v_lat is not null and (v_lat<-90 or v_lat>90 or v_lon<-180 or v_lon>180) then raise exception 'Place centroid coordinates are out of range.' using errcode='22023'; end if;

  select count(*)::integer,min(id::text)::uuid
    into v_area_count,v_area_id
  from local_intel.geographic_areas
  where verification_state='source_verified'
    and lower(btrim(name))=lower(v_name)
    and area_type=v_area_type
    and (v_state is null or upper(coalesce(state,''))=v_state);
  if v_area_count>1 then raise exception 'Existing Shared Intelligence geography is ambiguous; identity adjudication required.' using errcode='23514'; end if;

  if v_area_count=0 then
    v_stable_key:='source:'||v_identity_namespace||':'||v_identity_key;
    if exists(select 1 from local_intel.geographic_areas where stable_key=v_stable_key) then
      raise exception 'Source geography identity stable key already exists with different locality semantics.' using errcode='23505';
    end if;
    insert into local_intel.geographic_areas(
      stable_key,area_type,name,state,primary_postal_code,county_name,
      centroid_latitude,centroid_longitude,centroid_precision,source_id,verification_state,metadata
    ) values (
      v_stable_key,v_area_type,v_name,v_state,
      nullif(btrim(v_fields->>'primaryPostalCode'),''),nullif(btrim(v_fields->>'countyName'),''),
      v_lat,v_lon,v_precision,v_source.id,'source_verified',
      jsonb_build_object(
        'origin','atlas_geography_resolution_gap','atlasAcquisitionAttemptId',v_attempt.id,
        'sourceIdentityNamespace',v_identity_namespace,'sourceIdentityKey',v_identity_key,
        'countryCode',v_country,'promotionBasis',p_promotion_basis
      )
    ) returning id into v_area_id;
    v_created_area:=true;
  else
    select * into v_existing_area from local_intel.geographic_areas where id=v_area_id;
  end if;

  v_identity_resolution:=reality.resolve_place_identity_service_v1(v_identity_namespace,v_identity_key);
  if v_identity_resolution->>'state'='resolved' then
    v_entity_id:=(v_identity_resolution->>'entityId')::uuid;
    select * into v_entity from reality.entities where id=v_entity_id and identity_state='canonical' and entity_kind='place';
    select * into v_profile from reality.place_profiles where entity_id=v_entity_id and profile_state='active';
    if v_entity.id is null or v_profile.entity_id is null
       or v_profile.place_kind<>v_place_kind or v_profile.country_code is distinct from v_country then
      raise exception 'Existing source identity resolves to an incompatible canonical Place.' using errcode='23514';
    end if;
    v_local_id_receipt:=reality.register_place_identity_key_service_v1(
      v_entity_id,'local_intel.geographic_areas.id',v_area_id::text,
      jsonb_build_object('sourceId',v_source.id,'sourceUrl',v_source.source_url,'verificationState','source_verified'),
      jsonb_build_object('contractVersion','ATLAS_CONTACT_SET_PAIRED_GEOGRAPHY_V1','promotionBasis',p_promotion_basis),
      jsonb_build_object('sourceIdentityNamespace',v_identity_namespace,'sourceIdentityKey',v_identity_key)
    );
    select stable_key into v_stable_key from local_intel.geographic_areas where id=v_area_id;
    v_local_stable_receipt:=reality.register_place_identity_key_service_v1(
      v_entity_id,'local_intel.geographic_areas.stable_key',v_stable_key,
      jsonb_build_object('sourceId',v_source.id,'sourceUrl',v_source.source_url,'verificationState','source_verified'),
      jsonb_build_object('contractVersion','ATLAS_CONTACT_SET_PAIRED_GEOGRAPHY_V1','promotionBasis',p_promotion_basis),
      jsonb_build_object('sourceGeographicAreaId',v_area_id)
    );
  elsif v_identity_resolution->>'state'='absent' then
    v_admission:=atlas.admit_shared_geographic_area_to_reality_service_v1(
      v_area_id,v_country,
      jsonb_build_object(
        'contractVersion','ATLAS_CONTACT_SET_PAIRED_GEOGRAPHY_V1','candidateId',v_candidate.id,
        'sourceIdentityNamespace',v_identity_namespace,'sourceIdentityKey',v_identity_key,
        'promotionBasis',p_promotion_basis
      )
    );
    v_entity_id:=(v_admission->>'entityId')::uuid;
  else
    raise exception 'Source Place identity key is bound invalidly; adjudication required.' using errcode='23514';
  end if;

  v_source_key_receipt:=reality.register_place_identity_key_service_v1(
    v_entity_id,v_identity_namespace,v_identity_key,
    jsonb_build_object('sourceId',v_source.id,'sourceUrl',v_source.source_url,'verificationState','source_verified'),
    jsonb_build_object('contractVersion','ATLAS_CONTACT_SET_PAIRED_GEOGRAPHY_V1','promotionBasis',p_promotion_basis),
    jsonb_build_object('sourceGeographicAreaId',v_area_id,'candidateId',v_candidate.id)
  );

  update local_intel.entity_ingestion_candidates
  set review_state='promoted',
      metadata=metadata||jsonb_build_object(
        'promotedGeographicAreaId',v_area_id,'canonicalPlaceEntityId',v_entity_id,
        'sourceIdentityNamespace',v_identity_namespace,'sourceIdentityKey',v_identity_key,
        'promotionBasis',p_promotion_basis
      ),
      updated_at=now()
  where id=v_candidate.id
  returning * into v_candidate;

  update local_intel.search_discovery_evidence
  set reconciliation_status='applied',reconciled_at=now(),updated_at=now()
  where ingestion_candidate_id=v_candidate.id and reconciliation_status in ('pending','candidate');

  return jsonb_build_object(
    'contractVersion','atlas_place_ingestion_candidate_promotion_v1','state','promoted',
    'candidateId',v_candidate.id,'createdGeographicArea',v_created_area,
    'geographicAreaId',v_area_id,'entityId',v_entity_id,'placeKind',v_place_kind,'countryCode',v_country,
    'sourceIdentity',jsonb_build_object('namespace',v_identity_namespace,'key',v_identity_key,'receipt',v_source_key_receipt),
    'admission',v_admission,
    'truthBoundary',jsonb_build_object(
      'requiredGeographyReferenceSource',true,'requiredExplicitSourceIdentity',true,
      'requiredExactPersistedReferenceMatch',true,'communicationAuthorized',false
    )
  );
end
$function$;

revoke all on function atlas.promote_place_ingestion_candidate_to_reality_service_v1(uuid,jsonb) from public,anon,authenticated;
grant execute on function atlas.promote_place_ingestion_candidate_to_reality_service_v1(uuid,jsonb) to service_role;
