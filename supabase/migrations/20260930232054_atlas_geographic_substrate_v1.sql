-- Atlas Geographic Substrate v1.
-- Source geography is evidence; canonical Place identity remains in Reality.

create extension if not exists postgis with schema extensions;

create schema if not exists geography;

create table if not exists geography.datasets (
  dataset_key text primary key,
  publisher text not null,
  dataset_name text not null,
  source_url text,
  geography_scope text not null default 'global',
  current_vintage text,
  identity_authority boolean not null default false,
  containment_authority boolean not null default false,
  geometry_authority boolean not null default false,
  geometry_priority integer not null default 100,
  license_label text,
  attribution text,
  dataset_state text not null default 'active' check (dataset_state in ('active','retired')),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (dataset_key ~ '^[a-z0-9][a-z0-9._:-]*$'),
  check (btrim(publisher)<>'' and btrim(dataset_name)<>'')
);

create table if not exists geography.source_features (
  id uuid primary key default gen_random_uuid(),
  dataset_key text not null references geography.datasets(dataset_key) on delete restrict,
  source_feature_key text not null,
  source_vintage text not null,
  identity_namespace text,
  identity_key text,
  feature_kind text not null,
  canonical_place_kind text references reality.place_kinds(place_kind) on delete restrict,
  display_name text not null,
  country_code text,
  administrative_codes jsonb not null default '{}'::jsonb check (jsonb_typeof(administrative_codes)='object'),
  properties jsonb not null default '{}'::jsonb check (jsonb_typeof(properties)='object'),
  source_evidence jsonb not null default '{}'::jsonb check (jsonb_typeof(source_evidence)='object'),
  geom extensions.geometry(Geometry,4326),
  centroid extensions.geometry(Point,4326),
  is_current boolean not null default true,
  feature_state text not null default 'active' check (feature_state in ('active','retired')),
  observed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(dataset_key,source_feature_key,source_vintage),
  check (btrim(source_feature_key)<>'' and btrim(source_vintage)<>'' and btrim(feature_kind)<>'' and btrim(display_name)<>''),
  check ((identity_namespace is null and identity_key is null) or (nullif(btrim(identity_namespace),'') is not null and nullif(btrim(identity_key),'') is not null)),
  check (identity_namespace is null or identity_namespace ~ '^[a-z0-9][a-z0-9._:-]*$'),
  check (country_code is null or country_code ~ '^[A-Z]{2}$')
);

create unique index if not exists geography_source_features_one_current_idx
  on geography.source_features(dataset_key,source_feature_key)
  where is_current and feature_state='active';
create index if not exists geography_source_features_identity_idx
  on geography.source_features(identity_namespace,identity_key)
  where identity_namespace is not null and identity_key is not null and feature_state='active';
create index if not exists geography_source_features_geom_gix
  on geography.source_features using gist(geom)
  where geom is not null and feature_state='active';
create index if not exists geography_source_features_centroid_gix
  on geography.source_features using gist(centroid)
  where centroid is not null and feature_state='active';

create table if not exists geography.place_feature_bindings (
  source_feature_id uuid primary key references geography.source_features(id) on delete restrict,
  place_entity_id uuid not null references reality.entities(id) on delete restrict,
  binding_state text not null default 'active' check (binding_state in ('active','retired')),
  binding_basis jsonb not null default '{}'::jsonb check (jsonb_typeof(binding_basis)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists geography_place_feature_bindings_place_idx
  on geography.place_feature_bindings(place_entity_id)
  where binding_state='active';

create table if not exists geography.source_relations (
  id uuid primary key default gen_random_uuid(),
  dataset_key text not null references geography.datasets(dataset_key) on delete restrict,
  source_relation_key text not null,
  source_vintage text not null,
  subject_identity_namespace text not null,
  subject_identity_key text not null,
  relationship_kind text not null,
  object_identity_namespace text not null,
  object_identity_key text not null,
  properties jsonb not null default '{}'::jsonb check (jsonb_typeof(properties)='object'),
  source_evidence jsonb not null default '{}'::jsonb check (jsonb_typeof(source_evidence)='object'),
  is_current boolean not null default true,
  relation_state text not null default 'active' check (relation_state in ('active','retired')),
  observed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(dataset_key,source_relation_key,source_vintage),
  check (subject_identity_namespace ~ '^[a-z0-9][a-z0-9._:-]*$'),
  check (object_identity_namespace ~ '^[a-z0-9][a-z0-9._:-]*$'),
  check (btrim(subject_identity_key)<>'' and btrim(object_identity_key)<>'' and btrim(relationship_kind)<>'')
);
create unique index if not exists geography_source_relations_one_current_idx
  on geography.source_relations(dataset_key,source_relation_key)
  where is_current and relation_state='active';

insert into geography.datasets(
  dataset_key,publisher,dataset_name,source_url,geography_scope,current_vintage,
  identity_authority,containment_authority,geometry_authority,geometry_priority,
  license_label,attribution,metadata
) values
  ('census.tiger','U.S. Census Bureau','TIGER/Line','https://www.census.gov/geographies/mapping-files/time-series/geo/tiger-line-file.html','US','2025',true,true,true,10,'U.S. Government public data','U.S. Census Bureau',jsonb_build_object('role','primary_legal_and_administrative_geography','contractVersion','ATLAS_GEOGRAPHIC_SUBSTRATE_V1')),
  ('usgs.gnis','U.S. Geological Survey / U.S. Board on Geographic Names','Geographic Names Information System','https://www.usgs.gov/us-board-on-geographic-names/download-gnis-data','US',null,true,false,false,30,'U.S. Government public data','USGS / U.S. Board on Geographic Names',jsonb_build_object('role','official_names_and_named_features','contractVersion','ATLAS_GEOGRAPHIC_SUBSTRATE_V1')),
  ('openstreetmap','OpenStreetMap contributors','OpenStreetMap','https://www.openstreetmap.org/','global',null,false,false,false,80,'ODbL','© OpenStreetMap contributors',jsonb_build_object('role','rich_physical_world_observation','canonicalIdentityAuthority',false,'contractVersion','ATLAS_GEOGRAPHIC_SUBSTRATE_V1'))
on conflict(dataset_key) do update set
  publisher=excluded.publisher,dataset_name=excluded.dataset_name,source_url=excluded.source_url,
  geography_scope=excluded.geography_scope,current_vintage=coalesce(excluded.current_vintage,geography.datasets.current_vintage),
  identity_authority=excluded.identity_authority,containment_authority=excluded.containment_authority,
  geometry_authority=excluded.geometry_authority,geometry_priority=excluded.geometry_priority,
  license_label=excluded.license_label,attribution=excluded.attribution,
  metadata=geography.datasets.metadata||excluded.metadata,updated_at=now();

create or replace function geography.upsert_source_feature_v1(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_dataset text:=nullif(lower(btrim(p_payload->>'datasetKey')),'');
  v_source_key text:=nullif(btrim(p_payload->>'sourceFeatureKey'),'');
  v_vintage text:=nullif(btrim(p_payload->>'sourceVintage'),'');
  v_namespace text:=nullif(lower(btrim(p_payload->>'identityNamespace')),'');
  v_identity_key text:=nullif(btrim(p_payload->>'identityKey'),'');
  v_feature_kind text:=nullif(lower(btrim(p_payload->>'featureKind')),'');
  v_place_kind text:=nullif(lower(btrim(p_payload->>'canonicalPlaceKind')),'');
  v_name text:=nullif(btrim(p_payload->>'displayName'),'');
  v_country text:=nullif(upper(btrim(p_payload->>'countryCode')),'');
  v_geom extensions.geometry(Geometry,4326);
  v_centroid extensions.geometry(Point,4326);
  v_existing geography.source_features%rowtype;
  v_row geography.source_features%rowtype;
  v_geojson text:=nullif(p_payload->>'geometryGeoJSON','');
begin
  if p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception 'Geographic source feature payload must be an object.' using errcode='22023'; end if;
  if v_dataset is null or v_source_key is null or v_vintage is null or v_feature_kind is null or v_name is null then raise exception 'datasetKey, sourceFeatureKey, sourceVintage, featureKind, and displayName are required.' using errcode='22023'; end if;
  if not exists(select 1 from geography.datasets d where d.dataset_key=v_dataset and d.dataset_state='active') then raise exception 'Active geographic dataset is required.' using errcode='P0002'; end if;
  if (v_namespace is null)<>(v_identity_key is null) then raise exception 'identityNamespace and identityKey must be supplied together.' using errcode='22023'; end if;
  if v_place_kind is not null and not exists(select 1 from reality.place_kinds k where k.place_kind=v_place_kind and k.kind_state='active') then raise exception 'canonicalPlaceKind must be an active Reality Place kind.' using errcode='23514'; end if;
  if v_country is not null and v_country !~ '^[A-Z]{2}$' then raise exception 'countryCode must be a two-letter uppercase code.' using errcode='22023'; end if;

  if v_geojson is not null then
    begin
      v_geom:=extensions.st_force2d(extensions.st_setsrid(extensions.st_geomfromgeojson(v_geojson),4326));
      if not extensions.st_isvalid(v_geom) then v_geom:=extensions.st_makevalid(v_geom); end if;
      v_geom:=extensions.st_collectionextract(v_geom,case when extensions.geometrytype(v_geom) in ('POLYGON','MULTIPOLYGON') then 3 when extensions.geometrytype(v_geom) in ('LINESTRING','MULTILINESTRING') then 2 else 1 end);
      if extensions.st_isempty(v_geom) then v_geom:=null; end if;
    exception when others then
      raise exception 'geometryGeoJSON could not be parsed as valid EPSG:4326 geometry.' using errcode='22023';
    end;
  end if;
  if v_geom is not null then
    v_centroid:=extensions.st_pointonsurface(v_geom)::extensions.geometry(Point,4326);
  elsif nullif(p_payload->>'centroidLongitude','') is not null or nullif(p_payload->>'centroidLatitude','') is not null then
    if nullif(p_payload->>'centroidLongitude','') is null or nullif(p_payload->>'centroidLatitude','') is null then raise exception 'centroidLongitude and centroidLatitude must be supplied together.' using errcode='22023'; end if;
    begin
      v_centroid:=extensions.st_setsrid(extensions.st_makepoint((p_payload->>'centroidLongitude')::double precision,(p_payload->>'centroidLatitude')::double precision),4326)::extensions.geometry(Point,4326);
    exception when invalid_text_representation then raise exception 'Centroid coordinates must be numeric.' using errcode='22023'; end;
  end if;

  update geography.source_features
     set is_current=false,updated_at=now()
   where dataset_key=v_dataset and source_feature_key=v_source_key and is_current and feature_state='active' and source_vintage<>v_vintage;

  select * into v_existing from geography.source_features
   where dataset_key=v_dataset and source_feature_key=v_source_key and source_vintage=v_vintage;

  if v_existing.id is null then
    insert into geography.source_features(
      dataset_key,source_feature_key,source_vintage,identity_namespace,identity_key,feature_kind,
      canonical_place_kind,display_name,country_code,administrative_codes,properties,source_evidence,
      geom,centroid,is_current,feature_state,observed_at
    ) values(
      v_dataset,v_source_key,v_vintage,v_namespace,v_identity_key,v_feature_kind,v_place_kind,v_name,v_country,
      coalesce(case when jsonb_typeof(p_payload->'administrativeCodes')='object' then p_payload->'administrativeCodes' end,'{}'::jsonb),
      coalesce(case when jsonb_typeof(p_payload->'properties')='object' then p_payload->'properties' end,'{}'::jsonb),
      coalesce(case when jsonb_typeof(p_payload->'sourceEvidence')='object' then p_payload->'sourceEvidence' end,'{}'::jsonb),
      v_geom,v_centroid,true,'active',coalesce(nullif(p_payload->>'observedAt','')::timestamptz,now())
    ) returning * into v_row;
  else
    update geography.source_features set
      identity_namespace=v_namespace,identity_key=v_identity_key,feature_kind=v_feature_kind,
      canonical_place_kind=v_place_kind,display_name=v_name,country_code=v_country,
      administrative_codes=coalesce(case when jsonb_typeof(p_payload->'administrativeCodes')='object' then p_payload->'administrativeCodes' end,'{}'::jsonb),
      properties=coalesce(case when jsonb_typeof(p_payload->'properties')='object' then p_payload->'properties' end,'{}'::jsonb),
      source_evidence=coalesce(case when jsonb_typeof(p_payload->'sourceEvidence')='object' then p_payload->'sourceEvidence' end,'{}'::jsonb),
      geom=v_geom,centroid=v_centroid,is_current=true,feature_state='active',updated_at=now()
    where id=v_existing.id returning * into v_row;
  end if;

  return jsonb_build_object('contractVersion','geography_source_feature_v1','sourceFeatureId',v_row.id,'datasetKey',v_row.dataset_key,'sourceFeatureKey',v_row.source_feature_key,'sourceVintage',v_row.source_vintage,'identityNamespace',v_row.identity_namespace,'identityKey',v_row.identity_key,'geometryPresent',v_row.geom is not null,'centroidPresent',v_row.centroid is not null,'canonicalPlaceKind',v_row.canonical_place_kind);
end
$function$;

create or replace function geography.upsert_source_relation_v1(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_dataset text:=nullif(lower(btrim(p_payload->>'datasetKey')),'');
  v_key text:=nullif(btrim(p_payload->>'sourceRelationKey'),'');
  v_vintage text:=nullif(btrim(p_payload->>'sourceVintage'),'');
  v_subject_ns text:=nullif(lower(btrim(p_payload->>'subjectIdentityNamespace')),'');
  v_subject_key text:=nullif(btrim(p_payload->>'subjectIdentityKey'),'');
  v_kind text:=nullif(lower(btrim(p_payload->>'relationshipKind')),'');
  v_object_ns text:=nullif(lower(btrim(p_payload->>'objectIdentityNamespace')),'');
  v_object_key text:=nullif(btrim(p_payload->>'objectIdentityKey'),'');
  v_row geography.source_relations%rowtype;
begin
  if p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception 'Geographic source relation payload must be an object.' using errcode='22023'; end if;
  if v_dataset is null or v_key is null or v_vintage is null or v_subject_ns is null or v_subject_key is null or v_kind is null or v_object_ns is null or v_object_key is null then raise exception 'Dataset, source relation key, vintage, subject identity, relationship kind, and object identity are required.' using errcode='22023'; end if;
  if not exists(select 1 from geography.datasets d where d.dataset_key=v_dataset and d.dataset_state='active') then raise exception 'Active geographic dataset is required.' using errcode='P0002'; end if;
  if not exists(select 1 from reality.relationship_kinds k where k.relationship_kind=v_kind and k.kind_state='active') then raise exception 'Active governed Reality relationship kind is required.' using errcode='23514'; end if;

  update geography.source_relations set is_current=false,updated_at=now()
   where dataset_key=v_dataset and source_relation_key=v_key and is_current and relation_state='active' and source_vintage<>v_vintage;

  insert into geography.source_relations(
    dataset_key,source_relation_key,source_vintage,subject_identity_namespace,subject_identity_key,
    relationship_kind,object_identity_namespace,object_identity_key,properties,source_evidence,is_current,relation_state,observed_at
  ) values(
    v_dataset,v_key,v_vintage,v_subject_ns,v_subject_key,v_kind,v_object_ns,v_object_key,
    coalesce(case when jsonb_typeof(p_payload->'properties')='object' then p_payload->'properties' end,'{}'::jsonb),
    coalesce(case when jsonb_typeof(p_payload->'sourceEvidence')='object' then p_payload->'sourceEvidence' end,'{}'::jsonb),
    true,'active',coalesce(nullif(p_payload->>'observedAt','')::timestamptz,now())
  )
  on conflict(dataset_key,source_relation_key,source_vintage) do update set
    subject_identity_namespace=excluded.subject_identity_namespace,subject_identity_key=excluded.subject_identity_key,
    relationship_kind=excluded.relationship_kind,object_identity_namespace=excluded.object_identity_namespace,object_identity_key=excluded.object_identity_key,
    properties=excluded.properties,source_evidence=excluded.source_evidence,is_current=true,relation_state='active',updated_at=now()
  returning * into v_row;

  return jsonb_build_object('contractVersion','geography_source_relation_v1','sourceRelationId',v_row.id,'datasetKey',v_row.dataset_key,'relationshipKind',v_row.relationship_kind);
end
$function$;

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
  v_lat numeric;
  v_lon numeric;
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
    return jsonb_build_object('contractVersion','authoritative_geography_feature_reality_admission_v1','state','existing','sourceFeatureId',v_feature.id,'entityId',v_binding.place_entity_id,'inserted',false);
  end if;

  v_resolution:=reality.resolve_place_identity_service_v1(v_feature.identity_namespace,v_feature.identity_key);
  if v_resolution->>'state'='resolved' then
    v_entity_id:=(v_resolution->>'entityId')::uuid;
    select * into v_entity from reality.entities where id=v_entity_id and identity_state='canonical' and entity_kind='place';
    select * into v_profile from reality.place_profiles where entity_id=v_entity_id and profile_state='active';
    if v_entity.id is null or v_profile.entity_id is null then raise exception 'Resolved Place identity is not a canonical active Place.' using errcode='23514'; end if;
    if v_profile.place_kind<>v_feature.canonical_place_kind then raise exception 'Authoritative feature Place kind conflicts with existing canonical Place profile.' using errcode='23514'; end if;
  elsif v_resolution->>'state'='absent' then
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
  else
    raise exception 'Authoritative Place identity is ambiguous or invalid and requires adjudication.' using errcode='23514';
  end if;

  insert into geography.place_feature_bindings(source_feature_id,place_entity_id,binding_basis)
  values(v_feature.id,v_entity_id,jsonb_build_object('contractVersion','ATLAS_GEOGRAPHIC_SUBSTRATE_V1','datasetKey',v_feature.dataset_key,'sourceVintage',v_feature.source_vintage,'admissionBasis',p_admission_basis))
  on conflict(source_feature_id) do update set
    place_entity_id=case when geography.place_feature_bindings.place_entity_id=excluded.place_entity_id then geography.place_feature_bindings.place_entity_id else geography.place_feature_bindings.place_entity_id end,
    updated_at=now()
  returning * into v_binding;
  if v_binding.place_entity_id<>v_entity_id then raise exception 'Source feature is already bound to a different canonical Place.' using errcode='23505'; end if;

  return jsonb_build_object('contractVersion','authoritative_geography_feature_reality_admission_v1','state',case when v_inserted then 'admitted' else 'bound_existing' end,'sourceFeatureId',v_feature.id,'datasetKey',v_feature.dataset_key,'entityId',v_entity_id,'inserted',v_inserted,'geometryPresent',v_feature.geom is not null,'communicationAuthorized',false);
end
$function$;

create or replace function atlas.admit_authoritative_geography_dataset_to_reality_service_v1(p_dataset_key text,p_source_vintage text,p_admission_basis jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_dataset text:=lower(btrim(coalesce(p_dataset_key,'')));
  v_vintage text:=btrim(coalesce(p_source_vintage,''));
  v_feature record;
  v_receipt jsonb;
  v_total integer:=0;
  v_inserted integer:=0;
  v_bound integer:=0;
begin
  if v_dataset='' or v_vintage='' then raise exception 'Dataset key and source vintage are required.' using errcode='22023'; end if;
  if not exists(select 1 from geography.datasets d where d.dataset_key=v_dataset and d.dataset_state='active' and d.identity_authority) then raise exception 'Active identity-authoritative dataset required.' using errcode='23514'; end if;
  for v_feature in
    select id from geography.source_features
    where dataset_key=v_dataset and source_vintage=v_vintage and is_current and feature_state='active' and canonical_place_kind is not null
    order by source_feature_key
  loop
    v_receipt:=atlas.admit_authoritative_geography_feature_to_reality_service_v1(v_feature.id,p_admission_basis);
    v_total:=v_total+1;
    if coalesce((v_receipt->>'inserted')::boolean,false) then v_inserted:=v_inserted+1; else v_bound:=v_bound+1; end if;
  end loop;
  return jsonb_build_object('contractVersion','authoritative_geography_dataset_reality_admission_v1','datasetKey',v_dataset,'sourceVintage',v_vintage,'processed',v_total,'insertedCanonicalPlaces',v_inserted,'boundExistingPlaces',v_bound,'communicationAuthorized',false);
end
$function$;

create or replace function atlas.admit_authoritative_geography_relation_to_reality_service_v1(p_source_relation_id uuid,p_admission_basis jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_relation geography.source_relations%rowtype;
  v_dataset geography.datasets%rowtype;
  v_subject jsonb;
  v_object jsonb;
  v_prop jsonb;
  v_prop_id uuid;
  v_receipt jsonb;
begin
  if p_source_relation_id is null then raise exception 'Source relation id is required.' using errcode='22023'; end if;
  if p_admission_basis is null or jsonb_typeof(p_admission_basis)<>'object' then raise exception 'Admission basis must be an object.' using errcode='22023'; end if;
  select * into v_relation from geography.source_relations where id=p_source_relation_id and is_current and relation_state='active';
  if v_relation.id is null then raise exception 'Current active geographic source relation not found.' using errcode='P0002'; end if;
  select * into v_dataset from geography.datasets where dataset_key=v_relation.dataset_key and dataset_state='active';
  if v_dataset.dataset_key is null or not v_dataset.containment_authority then raise exception 'Dataset is not authorized as a containment authority.' using errcode='23514'; end if;
  if v_relation.relationship_kind<>'contained_in' then raise exception 'Geographic substrate v1 auto-admits only contained_in relations.' using errcode='23514'; end if;

  v_subject:=reality.resolve_place_identity_service_v1(v_relation.subject_identity_namespace,v_relation.subject_identity_key);
  v_object:=reality.resolve_place_identity_service_v1(v_relation.object_identity_namespace,v_relation.object_identity_key);
  if v_subject->>'state'<>'resolved' or v_object->>'state'<>'resolved' then raise exception 'Both source relation identities must resolve to canonical Places before containment admission.' using errcode='23514'; end if;

  v_prop:=reality.record_relationship_proposition_service_v1(
    (v_subject->>'entityId')::uuid,'contained_in',(v_object->>'entityId')::uuid,'established',null,null,
    jsonb_build_object('contractVersion','ATLAS_GEOGRAPHIC_SUBSTRATE_V1','datasetKey',v_relation.dataset_key,'sourceRelationId',v_relation.id,'sourceVintage',v_relation.source_vintage,'properties',v_relation.properties),
    jsonb_build_object('sourceSystem','geographic_substrate','datasetKey',v_relation.dataset_key,'sourceRelationId',v_relation.id),
    'geographic_substrate:'||v_relation.id::text
  );
  v_prop_id:=(v_prop->>'propositionId')::uuid;
  if not exists(select 1 from reality.relationship_proposition_evidence e where e.proposition_id=v_prop_id and e.source_locator->>'sourceRelationId'=v_relation.id::text) then
    perform reality.add_relationship_proposition_evidence_service_v1(
      v_prop_id,'authoritative_geographic_relation',
      jsonb_build_object('datasetKey',v_relation.dataset_key,'sourceRelationId',v_relation.id,'sourceRelationKey',v_relation.source_relation_key),
      jsonb_build_object('relationshipKind',v_relation.relationship_kind,'sourceVintage',v_relation.source_vintage,'sourceEvidence',v_relation.source_evidence,'properties',v_relation.properties),
      'Authoritative geographic substrate containment assertion.',coalesce(v_relation.observed_at,v_relation.updated_at),
      jsonb_build_object('contractVersion','ATLAS_GEOGRAPHIC_SUBSTRATE_V1')
    );
  end if;
  v_receipt:=reality.adjudicate_relationship_proposition_service_v1(
    v_prop_id,'accept','Accepted from a dataset explicitly governed as an authoritative geographic containment source.',
    jsonb_build_object('contractVersion','ATLAS_GEOGRAPHIC_SUBSTRATE_V1','datasetKey',v_relation.dataset_key,'containmentAuthority',true,'admissionBasis',p_admission_basis),null
  );
  return jsonb_build_object('contractVersion','authoritative_geography_relation_reality_admission_v1','sourceRelationId',v_relation.id,'propositionId',v_prop_id,'receipt',v_receipt,'communicationAuthorized',false);
end
$function$;

create or replace function atlas.admit_authoritative_geography_relations_dataset_v1(p_dataset_key text,p_source_vintage text,p_admission_basis jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_dataset text:=lower(btrim(coalesce(p_dataset_key,'')));
  v_vintage text:=btrim(coalesce(p_source_vintage,''));
  v_row record;
  v_count integer:=0;
begin
  if not exists(select 1 from geography.datasets d where d.dataset_key=v_dataset and d.dataset_state='active' and d.containment_authority) then raise exception 'Active containment-authoritative dataset required.' using errcode='23514'; end if;
  for v_row in select id from geography.source_relations where dataset_key=v_dataset and source_vintage=v_vintage and is_current and relation_state='active' order by source_relation_key loop
    perform atlas.admit_authoritative_geography_relation_to_reality_service_v1(v_row.id,p_admission_basis);
    v_count:=v_count+1;
  end loop;
  return jsonb_build_object('contractVersion','authoritative_geography_relation_dataset_admission_v1','datasetKey',v_dataset,'sourceVintage',v_vintage,'processed',v_count,'communicationAuthorized',false);
end
$function$;

create or replace view geography.v_canonical_place_geometry_v1 as
select
  b.place_entity_id,
  e.display_name,
  pp.place_kind,
  pp.country_code,
  f.dataset_key,
  f.source_feature_key,
  f.source_vintage,
  f.feature_kind,
  f.geom,
  f.centroid,
  d.geometry_priority,
  f.properties,
  f.administrative_codes
from geography.place_feature_bindings b
join geography.source_features f on f.id=b.source_feature_id and f.is_current and f.feature_state='active'
join geography.datasets d on d.dataset_key=f.dataset_key and d.dataset_state='active' and d.geometry_authority
join reality.entities e on e.id=b.place_entity_id and e.identity_state='canonical' and e.entity_kind='place'
join reality.place_profiles pp on pp.entity_id=e.id and pp.profile_state='active'
where b.binding_state='active';

create or replace function geography.places_covering_point_v1(p_latitude double precision,p_longitude double precision,p_place_kinds text[] default null)
returns table(place_entity_id uuid,display_name text,place_kind text,country_code text,dataset_key text,source_feature_key text,source_vintage text,geometry_priority integer)
language sql
stable
security definer
set search_path to ''
as $function$
  with point_input as (
    select extensions.st_setsrid(extensions.st_makepoint(p_longitude,p_latitude),4326)::extensions.geometry(Point,4326) as p
  ), ranked as (
    select g.*,
      row_number() over(partition by g.place_entity_id order by g.geometry_priority asc,g.source_vintage desc,g.source_feature_key) as rn
    from geography.v_canonical_place_geometry_v1 g,point_input x
    where g.geom is not null
      and (p_place_kinds is null or g.place_kind=any(p_place_kinds))
      and extensions.st_covers(g.geom,x.p)
  )
  select place_entity_id,display_name,place_kind,country_code,dataset_key,source_feature_key,source_vintage,geometry_priority
  from ranked where rn=1
  order by case place_kind when 'physical_site' then 1 when 'postal_area' then 2 when 'locality' then 3 when 'administrative_area' then 4 when 'region' then 5 when 'country' then 6 else 99 end,display_name,place_entity_id;
$function$;

comment on schema geography is 'Atlas source-aware geographic substrate. Imported map observations live here; canonical identity remains in reality.entities.';
comment on table geography.source_features is 'Versioned source geography observations. A source feature is evidence, not automatically a canonical Reality Place.';
comment on table geography.place_feature_bindings is 'Governed binding from source geography observations to canonical Reality Place identities.';
comment on function atlas.admit_authoritative_geography_feature_to_reality_service_v1(uuid,jsonb) is 'Admits or binds a Place only when its dataset is explicitly governed as an identity authority.';
comment on function atlas.admit_authoritative_geography_relation_to_reality_service_v1(uuid,jsonb) is 'Promotes authoritative contained_in geography through the Reality relationship proposition and adjudication membrane.';
