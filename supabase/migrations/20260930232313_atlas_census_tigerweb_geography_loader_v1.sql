-- Atlas Census TIGERweb geography loader v1.
-- Loads source observations only; no canonical Reality truth is created by this loader.

update geography.datasets
set current_vintage='2026',
    source_url='https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb/tigerWMS_Current/MapServer',
    metadata=metadata||jsonb_build_object('apiService','TIGERweb/tigerWMS_Current','apiVintage','2026-01-01','loaderContract','ATLAS_CENSUS_TIGERWEB_LOADER_V1'),
    updated_at=now()
where dataset_key='census.tiger';

create or replace function geography.load_census_tigerweb_state_v1(
  p_state_fips text,
  p_source_vintage text default '2026',
  p_page_size integer default 100
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_state text:=btrim(coalesce(p_state_fips,''));
  v_vintage text:=btrim(coalesce(p_source_vintage,''));
  v_page_size integer:=greatest(1,least(coalesce(p_page_size,100),500));
  v_layer record;
  v_offset integer;
  v_url text;
  v_response extensions.http_response;
  v_body jsonb;
  v_feature jsonb;
  v_props jsonb;
  v_geoid text;
  v_state_geoid text;
  v_name text;
  v_receipt jsonb;
  v_loaded integer:=0;
  v_relations integer:=0;
  v_page_count integer;
  v_layer_counts jsonb:='{}'::jsonb;
begin
  if v_state !~ '^[0-9]{2}$' then raise exception 'state FIPS must be exactly two digits.' using errcode='22023'; end if;
  if v_vintage='' then raise exception 'source vintage is required.' using errcode='22023'; end if;

  for v_layer in
    select * from (values
      (80,'state','census_state','administrative_area','census.tiger.state.geoid'),
      (82,'county','census_county','administrative_area','census.tiger.county.geoid'),
      (28,'incorporated_place','census_incorporated_place','locality','census.tiger.place.geoid'),
      (30,'census_designated_place','census_designated_place','locality','census.tiger.place.geoid')
    ) as x(layer_id,layer_key,feature_kind,place_kind,identity_namespace)
  loop
    v_offset:=0;
    v_page_count:=0;
    loop
      v_url:='https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb/tigerWMS_Current/MapServer/'||v_layer.layer_id::text||
        '/query?where=STATE%3D%27'||v_state||'%27&outFields=*&returnGeometry=true&outSR=4326&resultOffset='||v_offset::text||
        '&resultRecordCount='||v_page_size::text||'&orderByFields=GEOID&f=geojson';
      v_response:=extensions.http_get(v_url::varchar);
      if v_response.status<>200 then raise exception 'Census TIGERweb request failed for layer % with HTTP status %',v_layer.layer_id,v_response.status using errcode='58000'; end if;
      begin v_body:=v_response.content::jsonb; exception when others then raise exception 'Census TIGERweb response was not valid JSON for layer %',v_layer.layer_id using errcode='58000'; end;
      if jsonb_typeof(v_body->'features')<>'array' then raise exception 'Census TIGERweb response did not contain a feature array for layer %',v_layer.layer_id using errcode='58000'; end if;
      v_page_count:=jsonb_array_length(v_body->'features');
      if v_page_count=0 then exit; end if;

      for v_feature in select value from jsonb_array_elements(v_body->'features')
      loop
        v_props:=coalesce(v_feature->'properties','{}'::jsonb);
        v_geoid:=nullif(btrim(v_props->>'GEOID'),'');
        v_state_geoid:=nullif(btrim(v_props->>'STATE'),'');
        v_name:=coalesce(nullif(btrim(v_props->>'BASENAME'),''),nullif(btrim(v_props->>'NAME'),''));
        if v_geoid is null or v_state_geoid is null or v_name is null then raise exception 'Census feature missing GEOID/STATE/name in layer %',v_layer.layer_id using errcode='23514'; end if;

        v_receipt:=geography.upsert_source_feature_v1(jsonb_build_object(
          'datasetKey','census.tiger',
          'sourceFeatureKey',v_layer.layer_key||':'||v_geoid,
          'sourceVintage',v_vintage,
          'identityNamespace',v_layer.identity_namespace,
          'identityKey',v_geoid,
          'featureKind',v_layer.feature_kind,
          'canonicalPlaceKind',v_layer.place_kind,
          'displayName',v_name,
          'countryCode','US',
          'administrativeCodes',jsonb_strip_nulls(jsonb_build_object(
            'stateFips',v_props->>'STATE','countyFips',v_props->>'COUNTY','placeFips',v_props->>'PLACE',
            'lsadc',v_props->>'LSADC','funcstat',v_props->>'FUNCSTAT','mtfcc',v_props->>'MTFCC',
            'nameStatisticalId',coalesce(v_props->>'PLACENS',v_props->>'COUNTYNS',v_props->>'STATENS')
          )),
          'properties',v_props,
          'sourceEvidence',jsonb_build_object(
            'publisher','U.S. Census Bureau','service','TIGERweb/tigerWMS_Current','layerId',v_layer.layer_id,
            'layerKey',v_layer.layer_key,'vintageDate','2026-01-01','requestUrl',v_url
          ),
          'geometryGeoJSON',(v_feature->'geometry')::text,
          'centroidLatitude',nullif(v_props->>'CENTLAT',''),
          'centroidLongitude',nullif(v_props->>'CENTLON',''),
          'observedAt',now()
        ));
        v_loaded:=v_loaded+1;
        v_layer_counts:=jsonb_set(v_layer_counts,array[v_layer.layer_key],to_jsonb(coalesce((v_layer_counts->>v_layer.layer_key)::integer,0)+1),true);

        if v_layer.layer_key in ('county','incorporated_place','census_designated_place') then
          perform geography.upsert_source_relation_v1(jsonb_build_object(
            'datasetKey','census.tiger',
            'sourceRelationKey',v_layer.layer_key||':'||v_geoid||':contained_in:state:'||v_state_geoid,
            'sourceVintage',v_vintage,
            'subjectIdentityNamespace',v_layer.identity_namespace,
            'subjectIdentityKey',v_geoid,
            'relationshipKind','contained_in',
            'objectIdentityNamespace','census.tiger.state.geoid',
            'objectIdentityKey',v_state_geoid,
            'properties',jsonb_build_object('relationBasis','Census state membership encoded by GEOID/STATE fields'),
            'sourceEvidence',jsonb_build_object('publisher','U.S. Census Bureau','service','TIGERweb/tigerWMS_Current','layerId',v_layer.layer_id,'sourceFeatureKey',v_layer.layer_key||':'||v_geoid,'vintageDate','2026-01-01'),
            'observedAt',now()
          ));
          v_relations:=v_relations+1;
        end if;
      end loop;

      v_offset:=v_offset+v_page_count;
      if v_page_count<v_page_size or not coalesce((v_body->>'exceededTransferLimit')::boolean,false) then exit; end if;
    end loop;
  end loop;

  return jsonb_build_object(
    'contractVersion','census_tigerweb_state_loader_v1',
    'datasetKey','census.tiger','sourceVintage',v_vintage,'stateFips',v_state,
    'featuresLoaded',v_loaded,'relationsLoaded',v_relations,'layerCounts',v_layer_counts,
    'sourceAuthority',jsonb_build_object('identity',true,'containment',true,'geometry',true),
    'canonicalTruthCreated',false,'communicationAuthorized',false
  );
end
$function$;

comment on function geography.load_census_tigerweb_state_v1(text,text,integer) is 'Bounded source-corpus ETL from the fixed U.S. Census TIGERweb current service. Loads state, county, incorporated-place, and CDP observations plus state containment assertions; it creates no canonical Reality truth by itself.';
