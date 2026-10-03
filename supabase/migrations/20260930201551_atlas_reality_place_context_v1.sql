-- ATLAS_REALITY_PLACE_CONTEXT_V1
-- Canonical Place profiles, spatial containment, and Shared Intelligence adapters.

create table if not exists reality.place_kinds (
  place_kind text primary key check (btrim(place_kind)<>''),
  display_name text not null check (btrim(display_name)<>''),
  description text not null default '',
  is_geographic_area boolean not null default false,
  can_contain_places boolean not null default false,
  kind_state text not null default 'active' check (kind_state in ('active','retired')),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  retired_at timestamptz
);

create table if not exists reality.place_profiles (
  entity_id uuid primary key references reality.entities(id) on delete restrict,
  place_kind text not null references reality.place_kinds(place_kind) on delete restrict,
  country_code text,
  centroid_latitude numeric,
  centroid_longitude numeric,
  coordinate_precision text,
  coordinate_reference text,
  profile_state text not null default 'active' check (profile_state in ('active','retired')),
  evidence jsonb not null default '{}'::jsonb check (jsonb_typeof(evidence)='object'),
  profile_basis jsonb not null default '{}'::jsonb check (jsonb_typeof(profile_basis)='object'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  retired_at timestamptz,
  check (country_code is null or country_code ~ '^[A-Z]{2}$'),
  check ((centroid_latitude is null and centroid_longitude is null and coordinate_precision is null and coordinate_reference is null)
      or (centroid_latitude between -90 and 90 and centroid_longitude between -180 and 180
          and nullif(btrim(coordinate_precision),'') is not null
          and nullif(btrim(coordinate_reference),'') is not null))
);

alter table reality.place_kinds enable row level security;
alter table reality.place_profiles enable row level security;
revoke all on reality.place_kinds from public,anon,authenticated;
revoke all on reality.place_profiles from public,anon,authenticated;
revoke insert,update,delete,truncate,references,trigger on reality.place_kinds from service_role;
revoke insert,update,delete,truncate,references,trigger on reality.place_profiles from service_role;
grant select on reality.place_kinds to service_role;
grant select on reality.place_profiles to service_role;

create index if not exists reality_place_profiles_place_kind_idx
  on reality.place_profiles(place_kind) where profile_state='active';

create or replace function reality.register_place_kind_service_v1(
  p_place_kind text,
  p_display_name text,
  p_description text default '',
  p_is_geographic_area boolean default false,
  p_can_contain_places boolean default false,
  p_metadata jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path to ''
as $function$
declare
  v_key text:=nullif(btrim(p_place_kind),'');
  v_existing reality.place_kinds%rowtype;
begin
  if v_key is null or nullif(btrim(p_display_name),'') is null then
    raise exception 'Place kind key and display name are required.' using errcode='22023';
  end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Place kind metadata must be a JSON object.' using errcode='22023';
  end if;
  select * into v_existing from reality.place_kinds where place_kind=v_key;
  if v_existing.place_kind is not null then
    if v_existing.kind_state='active'
       and v_existing.display_name=btrim(p_display_name)
       and v_existing.description=coalesce(p_description,'')
       and v_existing.is_geographic_area=p_is_geographic_area
       and v_existing.can_contain_places=p_can_contain_places
       and v_existing.metadata=p_metadata then
      return jsonb_build_object('contractVersion','reality_place_kind_registration_v1','placeKind',v_key,'state','existing');
    end if;
    raise exception 'Place kind % already exists with different semantics or state.',v_key using errcode='23505';
  end if;
  insert into reality.place_kinds(place_kind,display_name,description,is_geographic_area,can_contain_places,metadata)
  values(v_key,btrim(p_display_name),coalesce(p_description,''),p_is_geographic_area,p_can_contain_places,p_metadata);
  return jsonb_build_object('contractVersion','reality_place_kind_registration_v1','placeKind',v_key,'state','registered');
end
$function$;

create or replace function reality.establish_place_profile_service_v1(
  p_entity_id uuid,
  p_place_kind text,
  p_country_code text default null,
  p_centroid_latitude numeric default null,
  p_centroid_longitude numeric default null,
  p_coordinate_precision text default null,
  p_coordinate_reference text default null,
  p_evidence jsonb default '{}'::jsonb,
  p_profile_basis jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path to ''
as $function$
declare
  v_entity reality.entities%rowtype;
  v_existing reality.place_profiles%rowtype;
  v_kind text:=nullif(btrim(p_place_kind),'');
  v_country text:=nullif(upper(btrim(p_country_code)),'');
  v_precision text:=nullif(btrim(p_coordinate_precision),'');
  v_reference text:=nullif(btrim(p_coordinate_reference),'');
begin
  if p_entity_id is null then raise exception 'Place Entity id is required.' using errcode='22023'; end if;
  select * into v_entity from reality.entities where id=p_entity_id and identity_state='canonical';
  if v_entity.id is null then raise exception 'Canonical Reality Entity required for Place profile.' using errcode='P0002'; end if;
  if v_entity.entity_kind<>'place' then raise exception 'Place profile requires entity_kind=place.' using errcode='23514'; end if;
  if v_kind is null or not exists(select 1 from reality.place_kinds k where k.place_kind=v_kind and k.kind_state='active') then raise exception 'Active governed Place kind required.' using errcode='23514'; end if;
  if v_country is not null and v_country !~ '^[A-Z]{2}$' then raise exception 'country_code must be a two-letter uppercase code.' using errcode='22023'; end if;
  if (p_centroid_latitude is null) <> (p_centroid_longitude is null) then raise exception 'Centroid latitude and longitude must be supplied together.' using errcode='22023'; end if;
  if p_centroid_latitude is not null then
    if p_centroid_latitude not between -90 and 90 or p_centroid_longitude not between -180 and 180 then raise exception 'Centroid coordinates are out of range.' using errcode='22023'; end if;
    if v_precision is null then raise exception 'Coordinate precision is required when centroid coordinates are supplied.' using errcode='22023'; end if;
    v_reference:=coalesce(v_reference,'EPSG:4326');
  else
    if v_precision is not null or v_reference is not null then raise exception 'Coordinate precision/reference require centroid coordinates.' using errcode='22023'; end if;
  end if;
  if p_evidence is null or jsonb_typeof(p_evidence)<>'object' or p_profile_basis is null or jsonb_typeof(p_profile_basis)<>'object' or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Place profile evidence, basis, and metadata must be JSON objects.' using errcode='22023';
  end if;

  select * into v_existing from reality.place_profiles where entity_id=p_entity_id;
  if v_existing.entity_id is not null then
    if v_existing.profile_state='active'
       and v_existing.place_kind=v_kind
       and v_existing.country_code is not distinct from v_country
       and v_existing.centroid_latitude is not distinct from p_centroid_latitude
       and v_existing.centroid_longitude is not distinct from p_centroid_longitude
       and v_existing.coordinate_precision is not distinct from v_precision
       and v_existing.coordinate_reference is not distinct from v_reference
       and v_existing.evidence=p_evidence
       and v_existing.profile_basis=p_profile_basis
       and v_existing.metadata=p_metadata then
      return jsonb_build_object('contractVersion','reality_place_profile_v1','entityId',p_entity_id,'placeKind',v_kind,'state','existing');
    end if;
    raise exception 'Place profile already exists with different semantics or state; explicit supersession is required.' using errcode='23505';
  end if;

  insert into reality.place_profiles(entity_id,place_kind,country_code,centroid_latitude,centroid_longitude,coordinate_precision,coordinate_reference,evidence,profile_basis,metadata)
  values(p_entity_id,v_kind,v_country,p_centroid_latitude,p_centroid_longitude,v_precision,v_reference,p_evidence,p_profile_basis,p_metadata);

  return jsonb_build_object('contractVersion','reality_place_profile_v1','entityId',p_entity_id,'placeKind',v_kind,'state','established');
end
$function$;

-- Universal Place kinds. Extensible; these do not exhaust the ontology.
select reality.register_place_kind_service_v1('physical_site','Physical site','A physical site, venue, campus, facility, parcel-scale place, or other bounded real-world site.',false,true,jsonb_build_object('coreContract','ATLAS_REALITY_PLACE_CONTEXT_V1'));
select reality.register_place_kind_service_v1('locality','Locality','A named locality such as a city, town, village, or comparable settlement.',true,true,jsonb_build_object('coreContract','ATLAS_REALITY_PLACE_CONTEXT_V1'));
select reality.register_place_kind_service_v1('administrative_area','Administrative area','A governed administrative geographic area such as a county, province, or state.',true,true,jsonb_build_object('coreContract','ATLAS_REALITY_PLACE_CONTEXT_V1'));
select reality.register_place_kind_service_v1('region','Region','A geographic region that may cross or compose administrative areas.',true,true,jsonb_build_object('coreContract','ATLAS_REALITY_PLACE_CONTEXT_V1'));
select reality.register_place_kind_service_v1('postal_area','Postal area','A geography established for postal addressing or delivery.',true,true,jsonb_build_object('coreContract','ATLAS_REALITY_PLACE_CONTEXT_V1'));
select reality.register_place_kind_service_v1('country','Country','A country-level geographic place.',true,true,jsonb_build_object('coreContract','ATLAS_REALITY_PLACE_CONTEXT_V1'));

-- Spatial topology primitives.
select reality.register_topology_axis_service_v1(
  'spatial_containment','Spatial containment','Universal acyclic spatial membership/containment axis.',true,'acyclic',jsonb_build_object('coreContract','ATLAS_REALITY_PLACE_CONTEXT_V1')
);
select reality.register_presence_class_service_v1(
  'spatial_membership','Spatial membership','Derived spatial presence or containment membership.','direct',jsonb_build_object('coreContract','ATLAS_REALITY_PLACE_CONTEXT_V1')
);
select reality.register_relationship_kind_service_v1(
  'located_in','Located in','The subject Entity is spatially located within the object Place.',null,false,null,array['place'],jsonb_build_object('coreContract','ATLAS_REALITY_PLACE_CONTEXT_V1')
);
select reality.register_relationship_kind_service_v1(
  'contained_in','Contained in','The subject Place is spatially contained within the object Place.',null,false,array['place'],array['place'],jsonb_build_object('coreContract','ATLAS_REALITY_PLACE_CONTEXT_V1')
);
select reality.register_relationship_topology_semantics_service_v1(
  'located_in','spatial_containment',true,'subject_to_object',true,true,'spatial_membership',jsonb_build_object('coreContract','ATLAS_REALITY_PLACE_CONTEXT_V1')
);
select reality.register_relationship_topology_semantics_service_v1(
  'contained_in','spatial_containment',true,'subject_to_object',true,true,'spatial_membership',jsonb_build_object('coreContract','ATLAS_REALITY_PLACE_CONTEXT_V1')
);

create or replace function atlas.admit_shared_intelligence_geographic_area_to_reality_service_v1(
  p_geographic_area_id uuid,
  p_place_kind text default null,
  p_country_code text default null,
  p_admission_basis jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path to ''
as $function$
declare
  v_source local_intel.geographic_areas%rowtype;
  v_existing reality.entities%rowtype;
  v_collision uuid;
  v_place_kind text;
  v_stable_key text;
  v_inserted boolean:=false;
  v_profile jsonb;
begin
  if p_geographic_area_id is null then raise exception 'Shared Intelligence geographic area id is required.' using errcode='22023'; end if;
  if p_admission_basis is null or jsonb_typeof(p_admission_basis)<>'object' then raise exception 'Admission basis must be a JSON object.' using errcode='22023'; end if;
  select * into v_source from local_intel.geographic_areas where id=p_geographic_area_id;
  if v_source.id is null then raise exception 'Shared Intelligence geographic area not found.' using errcode='P0002'; end if;
  if nullif(btrim(v_source.stable_key),'') is null or nullif(btrim(v_source.name),'') is null or nullif(btrim(v_source.area_type),'') is null then raise exception 'Shared Intelligence geographic area is missing identity fields.' using errcode='23514'; end if;

  v_place_kind:=coalesce(nullif(btrim(p_place_kind),''),btrim(v_source.area_type));
  if not exists(select 1 from reality.place_kinds where place_kind=v_place_kind and kind_state='active') then raise exception 'No active Reality Place kind matches the requested/source geographic area type: %',v_place_kind using errcode='23514'; end if;
  v_stable_key:='place:'||btrim(v_source.stable_key);

  select * into v_existing from reality.entities where id=v_source.id;
  if v_existing.id is null then
    select id into v_collision from reality.entities where stable_key=v_stable_key and id<>v_source.id limit 1;
    if v_collision is not null then raise exception 'Reality Place stable-key collision requires identity adjudication before admission.' using errcode='23505'; end if;
    insert into reality.entities(id,stable_key,entity_kind,display_name,identity_state,metadata)
    values(v_source.id,v_stable_key,'place',v_source.name,'canonical',jsonb_build_object(
      'admittedFrom','shared_intelligence_geographic_area',
      'sharedIntelligenceGeographicAreaId',v_source.id,
      'sharedIntelligenceStableKey',v_source.stable_key,
      'sharedIntelligenceVerificationState',v_source.verification_state,
      'sharedIntelligenceSourceId',v_source.source_id,
      'admissionBasis',p_admission_basis
    ));
    v_inserted:=true;
  else
    if v_existing.identity_state<>'canonical' or v_existing.entity_kind<>'place' then raise exception 'Existing Reality Entity for geographic area is not a canonical Place; adjudication required.' using errcode='23514'; end if;
    if v_existing.stable_key<>v_stable_key then raise exception 'Existing Reality Place stable key differs from geographic-area canonical key; adjudication required.' using errcode='23514'; end if;
  end if;

  v_profile:=reality.establish_place_profile_service_v1(
    v_source.id,v_place_kind,p_country_code,v_source.centroid_latitude,v_source.centroid_longitude,
    case when v_source.centroid_latitude is null then null else v_source.centroid_precision end,
    case when v_source.centroid_latitude is null then null else 'EPSG:4326' end,
    jsonb_strip_nulls(jsonb_build_object(
      'sourceSystem','shared_intelligence','geographicAreaId',v_source.id,'sourceId',v_source.source_id,
      'verificationState',v_source.verification_state,'primaryPostalCode',v_source.primary_postal_code,'countyName',v_source.county_name
    )),
    p_admission_basis,
    jsonb_build_object('sharedIntelligenceAreaType',v_source.area_type,'sharedIntelligenceStableKey',v_source.stable_key)
  );

  return jsonb_build_object(
    'contractVersion','shared_intelligence_geographic_area_reality_admission_v1',
    'entityId',v_source.id,'stableKey',v_stable_key,'displayName',v_source.name,'placeKind',v_place_kind,
    'inserted',v_inserted,'profile',v_profile,'identityRule','preserve_shared_intelligence_geographic_area_uuid_no_duplicate_referent'
  );
end
$function$;

create or replace function atlas.propose_shared_intelligence_entity_geography_to_reality_service_v1(
  p_entity_geographic_area_id uuid,
  p_idempotency_key text default null
) returns jsonb
language plpgsql security definer set search_path to ''
as $function$
declare
  v_link local_intel.entity_geographic_areas%rowtype;
  v_subject reality.entities%rowtype;
  v_place reality.entities%rowtype;
  v_prop jsonb;
  v_prop_id uuid;
  v_key text;
begin
  if p_entity_geographic_area_id is null then raise exception 'Shared Intelligence entity-geographic-area id is required.' using errcode='22023'; end if;
  select * into v_link from local_intel.entity_geographic_areas where id=p_entity_geographic_area_id;
  if v_link.id is null then raise exception 'Shared Intelligence entity-geographic-area assertion not found.' using errcode='P0002'; end if;
  if v_link.relation_kind<>'located_in' then raise exception 'V1 adapter supports only located_in assertions.' using errcode='23514'; end if;

  select * into v_subject from reality.entities where id=v_link.entity_id and identity_state='canonical';
  if v_subject.id is null then raise exception 'Canonical Reality subject Entity must exist before geography proposition.' using errcode='23514'; end if;
  select * into v_place from reality.entities where id=v_link.geographic_area_id and identity_state='canonical' and entity_kind='place';
  if v_place.id is null then raise exception 'Canonical Reality Place must exist before geography proposition.' using errcode='23514'; end if;
  if not exists(select 1 from reality.place_profiles p where p.entity_id=v_place.id and p.profile_state='active') then raise exception 'Active Place profile required before geography proposition.' using errcode='23514'; end if;

  v_key:=coalesce(nullif(btrim(p_idempotency_key),''),'shared_intelligence_entity_geography:'||v_link.id::text);
  v_prop:=reality.record_relationship_proposition_service_v1(
    v_subject.id,'located_in',v_place.id,'observed',null,null,
    jsonb_build_object('adapterContract','ATLAS_REALITY_PLACE_CONTEXT_V1','sharedIntelligenceEntityGeographicAreaId',v_link.id,'evidenceBasis',v_link.evidence_basis,'verificationState',v_link.verification_state),
    jsonb_build_object('sourceSystem','shared_intelligence','sourceId',v_link.source_id,'sourceAssertionId',v_link.id),
    v_key
  );
  v_prop_id:=(v_prop->>'propositionId')::uuid;

  if not exists(
    select 1 from reality.relationship_proposition_evidence e
    where e.proposition_id=v_prop_id and e.source_locator->>'sharedIntelligenceEntityGeographicAreaId'=v_link.id::text
  ) then
    perform reality.add_relationship_proposition_evidence_service_v1(
      v_prop_id,'shared_intelligence_geographic_assertion',
      jsonb_strip_nulls(jsonb_build_object('sharedIntelligenceEntityGeographicAreaId',v_link.id,'sourceId',v_link.source_id)),
      jsonb_build_object('relationKind',v_link.relation_kind,'evidenceBasis',v_link.evidence_basis,'verificationState',v_link.verification_state,'metadata',v_link.metadata),
      'Shared Intelligence geographic assertion proposed for governed Reality adjudication.',v_link.updated_at,
      jsonb_build_object('adapterContract','ATLAS_REALITY_PLACE_CONTEXT_V1')
    );
  end if;

  return jsonb_build_object(
    'contractVersion','shared_intelligence_entity_geography_proposal_v1',
    'sourceAssertionId',v_link.id,'propositionId',v_prop_id,
    'receipt',reality.relationship_proposition_receipt_v1(v_prop_id),
    'autoAdjudicated',false
  );
end
$function$;

revoke all on function reality.register_place_kind_service_v1(text,text,text,boolean,boolean,jsonb) from public,anon,authenticated;
revoke all on function reality.establish_place_profile_service_v1(uuid,text,text,numeric,numeric,text,text,jsonb,jsonb,jsonb) from public,anon,authenticated;
revoke all on function atlas.admit_shared_intelligence_geographic_area_to_reality_service_v1(uuid,text,text,jsonb) from public,anon,authenticated;
revoke all on function atlas.propose_shared_intelligence_entity_geography_to_reality_service_v1(uuid,text) from public,anon,authenticated;
grant execute on function reality.register_place_kind_service_v1(text,text,text,boolean,boolean,jsonb) to service_role;
grant execute on function reality.establish_place_profile_service_v1(uuid,text,text,numeric,numeric,text,text,jsonb,jsonb,jsonb) to service_role;
grant execute on function atlas.admit_shared_intelligence_geographic_area_to_reality_service_v1(uuid,text,text,jsonb) to service_role;
grant execute on function atlas.propose_shared_intelligence_entity_geography_to_reality_service_v1(uuid,text) to service_role;
