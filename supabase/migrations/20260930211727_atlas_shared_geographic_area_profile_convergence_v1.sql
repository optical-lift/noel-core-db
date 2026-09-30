-- ATLAS_REALITY_PLACE_RESOLUTION_V1 hardening: source identity may converge onto an existing canonical Place profile.

create or replace function atlas.admit_shared_geographic_area_to_reality_service_v1(
  p_geographic_area_id uuid,
  p_country_code text,
  p_admission_basis jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path to ''
as $function$
declare
  v_area local_intel.geographic_areas%rowtype;
  v_source local_intel.sources%rowtype;
  v_country text:=upper(btrim(coalesce(p_country_code,'')));
  v_place_kind text;
  v_existing_resolution jsonb;
  v_entity_id uuid;
  v_existing_entity reality.entities%rowtype;
  v_existing_profile reality.place_profiles%rowtype;
  v_stable_key text;
  v_slug text;
  v_inserted boolean:=false;
  v_profile jsonb;
  v_key_by_id jsonb;
  v_key_by_stable jsonb;
begin
  if p_geographic_area_id is null then raise exception 'Shared Intelligence geographic-area id is required.' using errcode='22023'; end if;
  if v_country !~ '^[A-Z]{2}$' then raise exception 'Explicit two-letter country code is required for Shared Intelligence geographic-area admission.' using errcode='22023'; end if;
  if p_admission_basis is null or jsonb_typeof(p_admission_basis)<>'object' then raise exception 'Admission basis must be a JSON object.' using errcode='22023'; end if;

  select * into v_area from local_intel.geographic_areas where id=p_geographic_area_id;
  if v_area.id is null then raise exception 'Shared Intelligence geographic area not found.' using errcode='P0002'; end if;
  if v_area.verification_state<>'source_verified' then raise exception 'V1 admits only source-verified Shared Intelligence geographic areas.' using errcode='23514'; end if;
  if nullif(btrim(v_area.stable_key),'') is null or nullif(btrim(v_area.name),'') is null then raise exception 'Shared Intelligence geographic area is missing stable identity fields.' using errcode='23514'; end if;

  v_place_kind:=case v_area.area_type
    when 'locality' then 'locality'
    when 'administrative_area' then 'administrative_area'
    when 'region' then 'region'
    when 'postal_area' then 'postal_area'
    when 'country' then 'country'
    else null end;
  if v_place_kind is null then raise exception 'Unsupported Shared Intelligence geographic area type: %',v_area.area_type using errcode='23514'; end if;
  if v_area.source_id is not null then select * into v_source from local_intel.sources where id=v_area.source_id; end if;

  v_existing_resolution:=reality.resolve_place_identity_service_v1('local_intel.geographic_areas.id',v_area.id::text);
  if v_existing_resolution->>'state'='resolved' then
    v_entity_id:=(v_existing_resolution->>'entityId')::uuid;
  elsif v_existing_resolution->>'state'<>'absent' then
    raise exception 'Existing Shared Intelligence geographic-area identity binding is invalid.' using errcode='23514';
  else
    v_existing_resolution:=reality.resolve_place_identity_service_v1('local_intel.geographic_areas.stable_key',v_area.stable_key);
    if v_existing_resolution->>'state'='resolved' then
      v_entity_id:=(v_existing_resolution->>'entityId')::uuid;
    elsif v_existing_resolution->>'state'<>'absent' then
      raise exception 'Existing Shared Intelligence geographic stable-key binding is invalid.' using errcode='23514';
    end if;
  end if;

  if v_entity_id is null then
    select * into v_existing_entity from reality.entities where id=v_area.id;
    if v_existing_entity.id is not null then
      if v_existing_entity.identity_state<>'canonical' or v_existing_entity.entity_kind<>'place' then
        raise exception 'Shared Intelligence geographic-area UUID collides with a non-Place Reality Entity.' using errcode='23505';
      end if;
      v_entity_id:=v_existing_entity.id;
    else
      v_slug:=btrim(regexp_replace(lower(v_area.stable_key),'[^a-z0-9]+','-','g'),'-');
      v_stable_key:='place:'||lower(v_country)||':'||replace(v_place_kind,'_','-')||':'||v_slug;
      if exists(select 1 from reality.entities e where e.stable_key=v_stable_key and e.id<>v_area.id) then
        raise exception 'Computed canonical Place stable key already belongs to another Reality Entity; identity adjudication required.' using errcode='23505';
      end if;
      insert into reality.entities(id,stable_key,entity_kind,display_name,identity_state,metadata)
      values(
        v_area.id,v_stable_key,'place',v_area.name,'canonical',
        jsonb_strip_nulls(jsonb_build_object(
          'admittedFrom','shared_intelligence_geographic_area',
          'sharedIntelligenceGeographicAreaId',v_area.id,
          'sharedIntelligenceStableKey',v_area.stable_key,
          'sharedIntelligenceAreaType',v_area.area_type,
          'sourceId',v_area.source_id,
          'admissionBasis',p_admission_basis
        ))
      );
      v_entity_id:=v_area.id;
      v_inserted:=true;
    end if;
  end if;

  select * into v_existing_profile from reality.place_profiles where entity_id=v_entity_id;
  if v_existing_profile.entity_id is not null then
    if v_existing_profile.profile_state<>'active'
       or v_existing_profile.place_kind<>v_place_kind
       or v_existing_profile.country_code is distinct from v_country then
      raise exception 'Existing canonical Place profile conflicts on Place kind, country, or state; explicit identity/profile adjudication required.' using errcode='23514';
    end if;
    v_profile:=jsonb_build_object(
      'contractVersion','reality_place_profile_v1','entityId',v_entity_id,
      'placeKind',v_existing_profile.place_kind,'state','existing',
      'sourceEvidenceAction','identity_key_only'
    );
  else
    v_profile:=reality.establish_place_profile_service_v1(
      v_entity_id,v_place_kind,v_country,
      v_area.centroid_latitude,v_area.centroid_longitude,
      case when v_area.centroid_latitude is null then null else v_area.centroid_precision end,
      case when v_area.centroid_latitude is null then null else 'EPSG:4326' end,
      jsonb_strip_nulls(jsonb_build_object(
        'sourceSystem','shared_intelligence','sourceGeographicAreaId',v_area.id,'sourceId',v_area.source_id,
        'sourceUrl',v_source.source_url,'sourceKind',v_source.source_kind,'publisher',v_source.publisher,'title',v_source.title,
        'verificationState',v_area.verification_state
      )),
      jsonb_build_object(
        'contractVersion','ATLAS_REALITY_PLACE_RESOLUTION_V1','adapter','local_intel.geographic_areas',
        'sourceStableKey',v_area.stable_key,'admissionBasis',p_admission_basis
      ),
      jsonb_strip_nulls(jsonb_build_object(
        'sourceStableKey',v_area.stable_key,'sourceAreaType',v_area.area_type,'state',v_area.state,
        'primaryPostalCode',v_area.primary_postal_code,'countyName',v_area.county_name,'sourceMetadata',v_area.metadata
      ))
    );
  end if;

  v_key_by_id:=reality.register_place_identity_key_service_v1(
    v_entity_id,'local_intel.geographic_areas.id',v_area.id::text,
    jsonb_strip_nulls(jsonb_build_object(
      'sourceId',v_area.source_id,'sourceUrl',v_source.source_url,'verificationState',v_area.verification_state,
      'centroidLatitude',v_area.centroid_latitude,'centroidLongitude',v_area.centroid_longitude,'centroidPrecision',v_area.centroid_precision
    )),
    jsonb_build_object('contractVersion','ATLAS_REALITY_PLACE_RESOLUTION_V1','sourceTable','local_intel.geographic_areas'),
    jsonb_build_object('sourceStableKey',v_area.stable_key)
  );
  v_key_by_stable:=reality.register_place_identity_key_service_v1(
    v_entity_id,'local_intel.geographic_areas.stable_key',v_area.stable_key,
    jsonb_strip_nulls(jsonb_build_object(
      'sourceId',v_area.source_id,'sourceUrl',v_source.source_url,'verificationState',v_area.verification_state,
      'centroidLatitude',v_area.centroid_latitude,'centroidLongitude',v_area.centroid_longitude,'centroidPrecision',v_area.centroid_precision
    )),
    jsonb_build_object('contractVersion','ATLAS_REALITY_PLACE_RESOLUTION_V1','sourceTable','local_intel.geographic_areas'),
    jsonb_build_object('sourceGeographicAreaId',v_area.id)
  );

  return jsonb_build_object(
    'contractVersion','shared_intelligence_geographic_area_reality_admission_v1',
    'sourceGeographicAreaId',v_area.id,'sourceStableKey',v_area.stable_key,
    'entityId',v_entity_id,'placeKind',v_place_kind,'countryCode',v_country,
    'inserted',v_inserted,'profile',v_profile,
    'identityKeys',jsonb_build_array(v_key_by_id,v_key_by_stable)
  );
end
$function$;
