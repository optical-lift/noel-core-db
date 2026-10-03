-- ATLAS_REALITY_PLACE_RESOLUTION_V1: Shared Intelligence geographic-area admission

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

  v_key_by_id:=reality.register_place_identity_key_service_v1(
    v_entity_id,'local_intel.geographic_areas.id',v_area.id::text,
    jsonb_strip_nulls(jsonb_build_object('sourceId',v_area.source_id,'sourceUrl',v_source.source_url,'verificationState',v_area.verification_state)),
    jsonb_build_object('contractVersion','ATLAS_REALITY_PLACE_RESOLUTION_V1','sourceTable','local_intel.geographic_areas'),
    jsonb_build_object('sourceStableKey',v_area.stable_key)
  );
  v_key_by_stable:=reality.register_place_identity_key_service_v1(
    v_entity_id,'local_intel.geographic_areas.stable_key',v_area.stable_key,
    jsonb_strip_nulls(jsonb_build_object('sourceId',v_area.source_id,'sourceUrl',v_source.source_url,'verificationState',v_area.verification_state)),
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

revoke all on function atlas.admit_shared_geographic_area_to_reality_service_v1(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function atlas.admit_shared_geographic_area_to_reality_service_v1(uuid,text,jsonb) to service_role;

create or replace function atlas.match_shared_geographic_area_reference_service_v1(
  p_name text,
  p_state text default null,
  p_area_type text default 'locality'
) returns jsonb
language plpgsql stable security definer set search_path to ''
as $function$
declare
  v_name text:=btrim(coalesce(p_name,''));
  v_state text:=nullif(upper(btrim(coalesce(p_state,''))), '');
  v_area_type text:=lower(btrim(coalesce(p_area_type,'')));
  v_count integer;
  v_candidates jsonb;
  v_single uuid;
begin
  if v_name='' or v_area_type='' then raise exception 'Geographic reference name and area type are required.' using errcode='22023'; end if;
  if v_area_type='locality' and v_state is null then raise exception 'Locality reference requires an explicit state/administrative hint in the Shared Intelligence v1 adapter.' using errcode='22023'; end if;

  select count(*)::integer,
         coalesce(jsonb_agg(jsonb_build_object(
           'sourceGeographicAreaId',ga.id,'sourceStableKey',ga.stable_key,'name',ga.name,'areaType',ga.area_type,
           'state',ga.state,'primaryPostalCode',ga.primary_postal_code,'verificationState',ga.verification_state
         ) order by ga.stable_key,ga.id),'[]'::jsonb),
         min(ga.id::text)::uuid
  into v_count,v_candidates,v_single
  from local_intel.geographic_areas ga
  where ga.verification_state='source_verified'
    and lower(btrim(ga.name))=lower(v_name)
    and ga.area_type=v_area_type
    and (v_state is null or upper(coalesce(ga.state,''))=v_state);

  if v_count=0 then
    return jsonb_build_object('contractVersion','shared_geographic_area_reference_match_v1','state','absent','name',v_name,'stateHint',v_state,'areaType',v_area_type,'candidates','[]'::jsonb);
  elsif v_count>1 then
    return jsonb_build_object('contractVersion','shared_geographic_area_reference_match_v1','state','ambiguous','name',v_name,'stateHint',v_state,'areaType',v_area_type,'candidates',v_candidates);
  end if;

  return jsonb_build_object('contractVersion','shared_geographic_area_reference_match_v1','state','matched_source','name',v_name,'stateHint',v_state,'areaType',v_area_type,'sourceGeographicAreaId',v_single,'candidates',v_candidates);
end
$function$;

revoke all on function atlas.match_shared_geographic_area_reference_service_v1(text,text,text) from public,anon,authenticated;
grant execute on function atlas.match_shared_geographic_area_reference_service_v1(text,text,text) to service_role;

create or replace function atlas.resolve_or_admit_shared_geographic_area_service_v1(
  p_name text,
  p_state text,
  p_country_code text,
  p_area_type text default 'locality',
  p_admission_basis jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path to ''
as $function$
declare
  v_match jsonb;
  v_admission jsonb;
begin
  v_match:=atlas.match_shared_geographic_area_reference_service_v1(p_name,p_state,p_area_type);
  if v_match->>'state'<>'matched_source' then
    return jsonb_build_object('contractVersion','shared_geographic_area_resolution_admission_v1','state',v_match->>'state','match',v_match);
  end if;

  v_admission:=atlas.admit_shared_geographic_area_to_reality_service_v1(
    (v_match->>'sourceGeographicAreaId')::uuid,p_country_code,p_admission_basis
  );

  return jsonb_build_object(
    'contractVersion','shared_geographic_area_resolution_admission_v1','state','resolved',
    'match',v_match,'admission',v_admission,'entityId',v_admission->>'entityId'
  );
end
$function$;

revoke all on function atlas.resolve_or_admit_shared_geographic_area_service_v1(text,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function atlas.resolve_or_admit_shared_geographic_area_service_v1(text,text,text,text,jsonb) to service_role;
