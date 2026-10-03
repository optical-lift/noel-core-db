-- Atlas Geographic Substrate convergence + named resolution v1.
-- Converges unique authoritative Census localities with existing Place identity and makes named Place resolution substrate-first.

create or replace function atlas.admit_authoritative_geography_feature_to_reality_service_v1(p_source_feature_id uuid,p_admission_basis jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_feature geography.source_features%rowtype;
  v_dataset geography.datasets%rowtype;
  v_resolution jsonb;
  v_entity reality.entities%rowtype;
  v_profile reality.place_profiles%rowtype;
  v_entity_id uuid;
  v_binding geography.place_feature_bindings%rowtype;
  v_inserted boolean:=false;
  v_converged boolean:=false;
  v_lat numeric;
  v_lon numeric;
  v_state_abbrev text;
  v_match_count integer:=0;
  v_match_id uuid;
begin
  if p_source_feature_id is null then raise exception 'Source feature id is required.' using errcode='22023'; end if;
  if p_admission_basis is null or jsonb_typeof(p_admission_basis)<>'object' then raise exception 'Admission basis must be an object.' using errcode='22023'; end if;
  select * into v_feature from geography.source_features where id=p_source_feature_id and is_current and feature_state='active';
  if v_feature.id is null then raise exception 'Current active geographic source feature not found.' using errcode='P0002'; end if;
  select * into v_dataset from geography.datasets where dataset_key=v_feature.dataset_key and dataset_state='active';
  if v_dataset.dataset_key is null or not v_dataset.identity_authority then raise exception 'Dataset is not authorized as a Place identity authority.' using errcode='23514'; end if;
  if v_feature.identity_namespace is null or v_feature.identity_key is null or v_feature.canonical_place_kind is null then raise exception 'Authoritative Place feature requires identity namespace/key and canonical Place kind.' using errcode='23514'; end if;

  select * into v_binding from geography.place_feature_bindings where source_feature_id=v_feature.id and binding_state='active';
  if v_binding.source_feature_id is not null then
    return jsonb_build_object('contractVersion','authoritative_geography_feature_reality_admission_v2','state','existing','sourceFeatureId',v_feature.id,'entityId',v_binding.place_entity_id,'inserted',false,'convergedExisting',false);
  end if;

  v_resolution:=reality.resolve_place_identity_service_v1(v_feature.identity_namespace,v_feature.identity_key);
  if v_resolution->>'state'='resolved' then
    v_entity_id:=(v_resolution->>'entityId')::uuid;
    select * into v_entity from reality.entities where id=v_entity_id and identity_state='canonical' and entity_kind='place';
    select * into v_profile from reality.place_profiles where entity_id=v_entity_id and profile_state='active';
    if v_entity.id is null or v_profile.entity_id is null then raise exception 'Resolved Place identity is not a canonical active Place.' using errcode='23514'; end if;
    if v_profile.place_kind<>v_feature.canonical_place_kind then raise exception 'Authoritative feature Place kind conflicts with existing canonical Place profile.' using errcode='23514'; end if;
  elsif v_resolution->>'state'='absent' then
    if v_feature.dataset_key='census.tiger' and v_feature.canonical_place_kind='locality' then
      select upper(nullif(btrim(s.properties->>'STUSAB'),'')) into v_state_abbrev
      from geography.source_features s
      where s.dataset_key='census.tiger'
        and s.source_vintage=v_feature.source_vintage
        and s.is_current and s.feature_state='active'
        and s.feature_kind='census_state'
        and s.identity_namespace='census.tiger.state.geoid'
        and s.identity_key=v_feature.administrative_codes->>'stateFips'
      limit 1;

      if v_state_abbrev is not null then
        select count(*)::integer,min(e.id::text)::uuid into v_match_count,v_match_id
        from reality.entities e
        join reality.place_profiles pp on pp.entity_id=e.id and pp.profile_state='active'
        where e.identity_state='canonical' and e.entity_kind='place'
          and lower(btrim(e.display_name))=lower(btrim(v_feature.display_name))
          and pp.place_kind=v_feature.canonical_place_kind
          and pp.country_code is not distinct from v_feature.country_code
          and upper(coalesce(pp.metadata->>'state',''))=v_state_abbrev;
      end if;
    end if;

    if v_match_count=1 then
      v_entity_id:=v_match_id;
      perform reality.register_place_identity_key_service_v1(
        v_entity_id,v_feature.identity_namespace,v_feature.identity_key,
        jsonb_build_object('datasetKey',v_feature.dataset_key,'sourceFeatureId',v_feature.id,'sourceEvidence',v_feature.source_evidence),
        jsonb_build_object('contractVersion','ATLAS_GEOGRAPHIC_SUBSTRATE_V1','identityAuthority',true,'sourceVintage',v_feature.source_vintage,'convergenceBasis','unique_exact_name_state_kind_country'),
        jsonb_build_object('sourceFeatureKey',v_feature.source_feature_key)
      );
      v_converged:=true;
    elsif v_match_count>1 then
      raise exception 'Authoritative source feature matches multiple existing canonical Places; explicit identity adjudication required.' using errcode='23514';
    else
      v_entity_id:=gen_random_uuid();
      insert into reality.entities(id,stable_key,entity_kind,display_name,identity_state,metadata)
      values(v_entity_id,'place:'||v_feature.identity_namespace||':'||v_feature.identity_key,'place',v_feature.display_name,'canonical',jsonb_build_object('admittedFrom','geographic_substrate','datasetKey',v_feature.dataset_key,'sourceFeatureId',v_feature.id,'sourceVintage',v_feature.source_vintage,'admissionBasis',p_admission_basis));
      if v_feature.centroid is not null then
        v_lon:=extensions.st_x(v_feature.centroid)::numeric;
        v_lat:=extensions.st_y(v_feature.centroid)::numeric;
      end if;
      perform reality.establish_place_profile_service_v1(
        v_entity_id,v_feature.canonical_place_kind,v_feature.country_code,v_lat,v_lon,
        case when v_feature.centroid is null then null else 'source_geometry_point_on_surface' end,
        case when v_feature.centroid is null then null else 'EPSG:4326' end,
        jsonb_build_object('datasetKey',v_feature.dataset_key,'sourceFeatureId',v_feature.id,'sourceEvidence',v_feature.source_evidence),
        jsonb_build_object('contractVersion','ATLAS_GEOGRAPHIC_SUBSTRATE_V1','sourceVintage',v_feature.source_vintage,'identityAuthority',true),
        jsonb_build_object('featureKind',v_feature.feature_kind,'administrativeCodes',v_feature.administrative_codes)
      );
      perform reality.register_place_identity_key_service_v1(
        v_entity_id,v_feature.identity_namespace,v_feature.identity_key,
        jsonb_build_object('datasetKey',v_feature.dataset_key,'sourceFeatureId',v_feature.id,'sourceEvidence',v_feature.source_evidence),
        jsonb_build_object('contractVersion','ATLAS_GEOGRAPHIC_SUBSTRATE_V1','identityAuthority',true,'sourceVintage',v_feature.source_vintage),
        jsonb_build_object('sourceFeatureKey',v_feature.source_feature_key)
      );
      v_inserted:=true;
    end if;
  else
    raise exception 'Authoritative Place identity is ambiguous or invalid and requires adjudication.' using errcode='23514';
  end if;

  insert into geography.place_feature_bindings(source_feature_id,place_entity_id,binding_basis)
  values(v_feature.id,v_entity_id,jsonb_build_object('contractVersion','ATLAS_GEOGRAPHIC_SUBSTRATE_V1','datasetKey',v_feature.dataset_key,'sourceVintage',v_feature.source_vintage,'admissionBasis',p_admission_basis,'convergedExisting',v_converged))
  on conflict(source_feature_id) do update set updated_at=now()
  returning * into v_binding;
  if v_binding.place_entity_id<>v_entity_id then raise exception 'Source feature is already bound to a different canonical Place.' using errcode='23505'; end if;

  return jsonb_build_object('contractVersion','authoritative_geography_feature_reality_admission_v2','state',case when v_inserted then 'admitted' when v_converged then 'converged_existing' else 'bound_existing' end,'sourceFeatureId',v_feature.id,'datasetKey',v_feature.dataset_key,'entityId',v_entity_id,'inserted',v_inserted,'convergedExisting',v_converged,'geometryPresent',v_feature.geom is not null,'communicationAuthorized',false);
end
$function$;

create or replace function geography.resolve_named_place_v1(
  p_name text,
  p_administrative_hint text default null,
  p_country_code text default null,
  p_place_kind text default 'locality'
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_name text:=nullif(btrim(p_name),'');
  v_hint text:=nullif(btrim(p_administrative_hint),'');
  v_country text:=nullif(upper(btrim(p_country_code)),'');
  v_kind text:=coalesce(nullif(lower(btrim(p_place_kind)),''),'locality');
  v_count integer:=0;
  v_entity_id uuid;
  v_matches jsonb:='[]'::jsonb;
begin
  if v_name is null then raise exception 'Place name is required.' using errcode='22023'; end if;
  if v_country is not null and v_country !~ '^[A-Z]{2}$' then raise exception 'country code must be two uppercase letters.' using errcode='22023'; end if;

  with candidates as (
    select distinct g.place_entity_id,g.display_name,g.place_kind,g.country_code,
      g.dataset_key,g.source_feature_key,g.source_vintage,
      sf.administrative_codes,sf.properties,
      state_sf.display_name as state_name,state_sf.properties->>'STUSAB' as state_abbrev
    from geography.v_canonical_place_geometry_v1 g
    join geography.source_features sf on sf.dataset_key=g.dataset_key and sf.source_feature_key=g.source_feature_key and sf.source_vintage=g.source_vintage
    left join geography.source_features state_sf
      on sf.dataset_key='census.tiger'
     and state_sf.dataset_key='census.tiger'
     and state_sf.source_vintage=sf.source_vintage
     and state_sf.feature_kind='census_state'
     and state_sf.identity_namespace='census.tiger.state.geoid'
     and state_sf.identity_key=sf.administrative_codes->>'stateFips'
     and state_sf.is_current and state_sf.feature_state='active'
    where lower(btrim(g.display_name))=lower(v_name)
      and g.place_kind=v_kind
      and (v_country is null or g.country_code=v_country)
      and (
        v_hint is null
        or upper(coalesce(state_sf.properties->>'STUSAB',''))=upper(v_hint)
        or lower(coalesce(state_sf.display_name,''))=lower(v_hint)
        or upper(coalesce(sf.administrative_codes->>'stateFips',''))=upper(v_hint)
      )
  )
  select count(*)::integer,min(place_entity_id::text)::uuid,
         coalesce(jsonb_agg(jsonb_build_object('entityId',place_entity_id,'displayName',display_name,'placeKind',place_kind,'countryCode',country_code,'datasetKey',dataset_key,'sourceFeatureKey',source_feature_key,'sourceVintage',source_vintage,'stateName',state_name,'stateAbbreviation',state_abbrev) order by display_name,place_entity_id),'[]'::jsonb)
  into v_count,v_entity_id,v_matches
  from candidates;

  return jsonb_build_object(
    'contractVersion','geographic_substrate_named_place_resolution_v1',
    'state',case when v_count=1 then 'resolved' when v_count=0 then 'absent' else 'ambiguous' end,
    'entityId',case when v_count=1 then v_entity_id else null end,
    'matchCount',v_count,'matches',v_matches,
    'query',jsonb_strip_nulls(jsonb_build_object('name',v_name,'administrativeHint',v_hint,'countryCode',v_country,'placeKind',v_kind))
  );
end
$function$;

create or replace function atlas.resolve_or_admit_place_reference_service_v1(p_reference jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare v_place_id uuid; v_identity_namespace text; v_identity_key text; v_name text; v_admin_hint text; v_country_code text; v_place_kind text; v_resolution jsonb; v_entity reality.entities%rowtype; v_profile reality.place_profiles%rowtype; v_modes integer:=0;
begin
  if p_reference is null or jsonb_typeof(p_reference)<>'object' then raise exception 'Place reference must be a JSON object.' using errcode='22023'; end if;
  if nullif(btrim(p_reference->>'placeEntityId'),'') is not null then v_modes:=v_modes+1; end if;
  if nullif(btrim(p_reference->>'identityNamespace'),'') is not null or nullif(btrim(p_reference->>'identityKey'),'') is not null then v_modes:=v_modes+1; end if;
  if nullif(btrim(p_reference->>'name'),'') is not null then v_modes:=v_modes+1; end if;
  if v_modes<>1 then raise exception 'Place reference must use exactly one identity mode: placeEntityId, identityNamespace+identityKey, or name.' using errcode='22023'; end if;
  if nullif(btrim(p_reference->>'placeEntityId'),'') is not null then
    begin v_place_id:=(p_reference->>'placeEntityId')::uuid; exception when invalid_text_representation then raise exception 'placeEntityId must be UUID.' using errcode='22023'; end;
    select * into v_entity from reality.entities where id=v_place_id and identity_state='canonical' and entity_kind='place'; select * into v_profile from reality.place_profiles where entity_id=v_place_id and profile_state='active';
    if v_entity.id is null or v_profile.entity_id is null then return jsonb_build_object('contractVersion','atlas_place_reference_resolution_v2','state','absent','reference',p_reference,'reason','canonical_place_not_found'); end if;
    return jsonb_build_object('contractVersion','atlas_place_reference_resolution_v2','state','resolved','reference',p_reference,'entityId',v_entity.id,'displayName',v_entity.display_name,'placeKind',v_profile.place_kind,'countryCode',v_profile.country_code,'resolutionMode','canonical_entity_id');
  end if;
  if nullif(btrim(p_reference->>'identityNamespace'),'') is not null or nullif(btrim(p_reference->>'identityKey'),'') is not null then
    v_identity_namespace:=nullif(btrim(p_reference->>'identityNamespace'),''); v_identity_key:=nullif(btrim(p_reference->>'identityKey'),'');
    if v_identity_namespace is null or v_identity_key is null then raise exception 'identityNamespace and identityKey are both required.' using errcode='22023'; end if;
    v_resolution:=reality.resolve_place_identity_service_v1(v_identity_namespace,v_identity_key);
    return jsonb_build_object('contractVersion','atlas_place_reference_resolution_v2','state',v_resolution->>'state','reference',p_reference,'entityId',v_resolution->>'entityId','displayName',v_resolution->>'displayName','placeKind',v_resolution->>'placeKind','countryCode',v_resolution->>'countryCode','resolutionMode','source_identity_key','identityResolution',v_resolution);
  end if;
  v_name:=nullif(btrim(p_reference->>'name'),''); v_admin_hint:=nullif(upper(btrim(coalesce(p_reference->>'administrativeHint',''))),''); v_country_code:=nullif(upper(btrim(coalesce(p_reference->>'countryCode',''))),''); v_place_kind:=coalesce(nullif(lower(btrim(p_reference->>'placeKind')),''),'locality');
  if v_country_code is null then raise exception 'Named Place reference requires countryCode.' using errcode='22023'; end if; if v_place_kind='locality' and v_admin_hint is null then raise exception 'Named locality reference requires administrativeHint.' using errcode='22023'; end if;

  v_resolution:=geography.resolve_named_place_v1(v_name,v_admin_hint,v_country_code,v_place_kind);
  if v_resolution->>'state'='resolved' then
    v_place_id:=(v_resolution->>'entityId')::uuid;
    select * into v_entity from reality.entities where id=v_place_id;
    select * into v_profile from reality.place_profiles where entity_id=v_place_id and profile_state='active';
    return jsonb_build_object('contractVersion','atlas_place_reference_resolution_v2','state','resolved','reference',p_reference,'entityId',v_place_id,'displayName',v_entity.display_name,'placeKind',v_profile.place_kind,'countryCode',v_profile.country_code,'resolutionMode','geographic_substrate_canonical_match','geographicResolution',v_resolution);
  elsif v_resolution->>'state'='ambiguous' then
    return jsonb_build_object('contractVersion','atlas_place_reference_resolution_v2','state','ambiguous','reference',p_reference,'resolutionMode','geographic_substrate_canonical_match','geographicResolution',v_resolution);
  end if;

  v_resolution:=atlas.resolve_or_admit_shared_geographic_area_service_v1(v_name,v_admin_hint,v_country_code,v_place_kind,jsonb_build_object('contractVersion','ATLAS_CONTACT_SET_PAIRED_GEOGRAPHY_V1','reference',p_reference));
  if v_resolution->>'state'='resolved' then return jsonb_build_object('contractVersion','atlas_place_reference_resolution_v2','state','resolved','reference',p_reference,'entityId',v_resolution->>'entityId','resolutionMode','shared_geographic_area_exact_match','resolution',v_resolution); end if;
  return jsonb_build_object('contractVersion','atlas_place_reference_resolution_v2','state',v_resolution->>'state','reference',p_reference,'resolutionMode','shared_geographic_area_exact_match','resolution',v_resolution,'geographicSubstrateResolution',geography.resolve_named_place_v1(v_name,v_admin_hint,v_country_code,v_place_kind));
end
$function$;
