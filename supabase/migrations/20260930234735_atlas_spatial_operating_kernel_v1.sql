-- Atlas Spatial Operating Kernel v1
-- Canonical entity geography remains in Reality. Operational subjects carry governed
-- spatial contexts that reference canonical Reality Places.

create table if not exists atlas.spatial_context_kinds (
  context_kind text primary key,
  display_name text not null,
  description text not null,
  requires_place boolean not null default true,
  allows_distance_limit boolean not null default false,
  kind_state text not null default 'active',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint spatial_context_kinds_key_v1 check (context_kind ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint spatial_context_kinds_state_v1 check (kind_state in ('active','retired')),
  constraint spatial_context_kinds_metadata_v1 check (jsonb_typeof(metadata)='object')
);

insert into atlas.spatial_context_kinds(context_kind,display_name,description,requires_place,allows_distance_limit,metadata)
values
('required_at','Required at','Physical presence at this canonical Place is required.',true,false,'{"operationalUse":"hard_spatial_requirement"}'::jsonb),
('occurs_at','Occurs at','The operation or event occurs at this canonical Place.',true,false,'{"operationalUse":"event_location"}'::jsonb),
('observed_at','Observed at','An observation was made at this canonical Place.',true,false,'{"operationalUse":"observation_location"}'::jsonb),
('origin','Origin','The operation originates at this canonical Place.',true,false,'{"operationalUse":"movement_origin"}'::jsonb),
('destination','Destination','The operation ends or is delivered at this canonical Place.',true,false,'{"operationalUse":"movement_destination"}'::jsonb),
('service_area','Service area','The subject is valid in or around this canonical Place.',true,true,'{"operationalUse":"territory"}'::jsonb),
('jurisdiction','Jurisdiction','This canonical Place defines an applicable jurisdictional scope.',true,false,'{"operationalUse":"authority_scope"}'::jsonb),
('preferred_near','Preferred near','Execution is preferred near this canonical Place within an optional radius.',true,true,'{"operationalUse":"soft_spatial_preference"}'::jsonb),
('base_at','Base at','This subject normally operates from this canonical Place.',true,false,'{"operationalUse":"operational_base"}'::jsonb),
('location_flexibility','Location flexibility','The subject explicitly does not require one canonical Place.',false,false,'{"operationalUse":"explicit_anywhere_or_remote"}'::jsonb)
on conflict (context_kind) do update
set display_name=excluded.display_name,
    description=excluded.description,
    requires_place=excluded.requires_place,
    allows_distance_limit=excluded.allows_distance_limit,
    kind_state='active',
    metadata=atlas.spatial_context_kinds.metadata || excluded.metadata,
    updated_at=now();

create table if not exists atlas.spatial_contexts (
  id uuid primary key default gen_random_uuid(),
  stable_key text not null unique,
  organization_id uuid,
  subject_kind text not null,
  subject_id uuid not null,
  context_kind text not null references atlas.spatial_context_kinds(context_kind) on delete restrict,
  place_entity_id uuid references reality.entities(id) on delete restrict,
  presence_mode text not null default 'physical',
  distance_limit_meters double precision,
  valid_from timestamptz,
  valid_until timestamptz,
  context_state text not null default 'active',
  basis jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  retired_at timestamptz,
  constraint spatial_contexts_stable_key_v1 check (stable_key ~ '^[a-zA-Z0-9][a-zA-Z0-9._:-]{2,255}$'),
  constraint spatial_contexts_subject_kind_v1 check (subject_kind ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint spatial_contexts_presence_mode_v1 check (presence_mode in ('physical','remote','either','unknown')),
  constraint spatial_contexts_distance_v1 check (distance_limit_meters is null or (distance_limit_meters>=0 and distance_limit_meters<=25000000)),
  constraint spatial_contexts_validity_v1 check (valid_until is null or valid_from is null or valid_until>valid_from),
  constraint spatial_contexts_state_v1 check (context_state in ('active','retired','superseded')),
  constraint spatial_contexts_basis_v1 check (jsonb_typeof(basis)='object'),
  constraint spatial_contexts_metadata_v1 check (jsonb_typeof(metadata)='object'),
  constraint spatial_contexts_retirement_v1 check ((context_state='active' and retired_at is null) or context_state in ('retired','superseded'))
);

create index if not exists spatial_contexts_subject_idx_v1
  on atlas.spatial_contexts(subject_kind,subject_id,context_state);
create index if not exists spatial_contexts_place_idx_v1
  on atlas.spatial_contexts(place_entity_id,context_kind,context_state)
  where place_entity_id is not null;
create index if not exists spatial_contexts_org_idx_v1
  on atlas.spatial_contexts(organization_id,context_state)
  where organization_id is not null;

alter table atlas.spatial_context_kinds enable row level security;
alter table atlas.spatial_contexts enable row level security;
revoke all on table atlas.spatial_context_kinds from public,anon,authenticated;
revoke all on table atlas.spatial_contexts from public,anon,authenticated;
grant select on table atlas.spatial_context_kinds to service_role;
grant select on table atlas.spatial_contexts to service_role;

create or replace function atlas.spatial_subject_exists_v1(p_subject_kind text,p_subject_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas'
as $function$
begin
  if p_subject_kind='work_item' then return exists(select 1 from atlas.work_items where id=p_subject_id); end if;
  if p_subject_kind='work_requirement' then return exists(select 1 from atlas.work_requirements where id=p_subject_id); end if;
  if p_subject_kind='planned_work_occurrence' then return exists(select 1 from atlas.planned_work_occurrences where id=p_subject_id); end if;
  if p_subject_kind='organization_responsibility' then return exists(select 1 from atlas.organization_responsibilities where id=p_subject_id); end if;
  if p_subject_kind='ledger' then return exists(select 1 from atlas.ledgers where id=p_subject_id); end if;
  if p_subject_kind='principal_capacity_block' then return exists(select 1 from atlas.principal_capacity_blocks where id=p_subject_id); end if;
  if p_subject_kind='owner_obligation' then return exists(select 1 from atlas.owner_obligations where id=p_subject_id); end if;
  if p_subject_kind='household_event' then return exists(select 1 from atlas.household_events where id=p_subject_id); end if;
  if p_subject_kind='operational_escalation' then return exists(select 1 from atlas.operational_escalations where id=p_subject_id); end if;
  if p_subject_kind='organization_ledger_entry' then return exists(select 1 from atlas.organization_ledger_entries where id=p_subject_id); end if;
  if p_subject_kind='communication_event' then return exists(select 1 from atlas.communication_events where id=p_subject_id); end if;
  if p_subject_kind='community_event' then return exists(select 1 from atlas.community_events where id=p_subject_id); end if;
  if p_subject_kind='object_activity_event' then return exists(select 1 from atlas.object_activity_events where id=p_subject_id); end if;
  if p_subject_kind='resource_event' then return exists(select 1 from atlas.resource_events where id=p_subject_id); end if;
  return false;
end
$function$;

create or replace function atlas.put_spatial_context_service_v1(
  p_stable_key text,
  p_subject_kind text,
  p_subject_id uuid,
  p_context_kind text,
  p_place_entity_id uuid default null,
  p_presence_mode text default 'physical',
  p_distance_limit_meters double precision default null,
  p_valid_from timestamptz default null,
  p_valid_until timestamptz default null,
  p_organization_id uuid default null,
  p_basis jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','reality'
as $function$
declare
  v_kind atlas.spatial_context_kinds%rowtype;
  v_existing atlas.spatial_contexts%rowtype;
  v_row atlas.spatial_contexts%rowtype;
begin
  if p_stable_key is null or p_stable_key !~ '^[a-zA-Z0-9][a-zA-Z0-9._:-]{2,255}$' then raise exception 'Valid spatial context stable key required.' using errcode='22023'; end if;
  if p_subject_id is null or not atlas.spatial_subject_exists_v1(p_subject_kind,p_subject_id) then raise exception 'Supported existing Atlas spatial subject required.' using errcode='P0002'; end if;
  if p_presence_mode not in ('physical','remote','either','unknown') then raise exception 'Unsupported presence mode.' using errcode='22023'; end if;
  if p_basis is null or jsonb_typeof(p_basis)<>'object' or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then raise exception 'Basis and metadata must be JSON objects.' using errcode='22023'; end if;
  if p_valid_until is not null and p_valid_from is not null and p_valid_until<=p_valid_from then raise exception 'Spatial validity end must follow start.' using errcode='22023'; end if;

  select * into v_kind from atlas.spatial_context_kinds where context_kind=p_context_kind and kind_state='active';
  if v_kind.context_kind is null then raise exception 'Active spatial context kind required.' using errcode='22023'; end if;
  if v_kind.requires_place and p_place_entity_id is null then raise exception 'This spatial context kind requires a canonical Place.' using errcode='22023'; end if;
  if not v_kind.requires_place and p_place_entity_id is not null then raise exception 'This spatial context kind must not bind a Place.' using errcode='22023'; end if;
  if not v_kind.allows_distance_limit and p_distance_limit_meters is not null then raise exception 'This spatial context kind does not accept a distance limit.' using errcode='22023'; end if;
  if p_distance_limit_meters is not null and (p_distance_limit_meters<0 or p_distance_limit_meters>25000000) then raise exception 'Distance limit outside supported range.' using errcode='22023'; end if;
  if p_context_kind='location_flexibility' and p_presence_mode not in ('remote','either') then raise exception 'Location flexibility must explicitly be remote or either.' using errcode='22023'; end if;
  if p_context_kind in ('required_at','occurs_at','observed_at','origin','destination','base_at') and p_presence_mode='remote' then raise exception 'Physical place context cannot be remote-only.' using errcode='22023'; end if;

  if p_place_entity_id is not null and not exists(
    select 1 from reality.entities e join reality.place_profiles pp on pp.entity_id=e.id and pp.profile_state='active'
    where e.id=p_place_entity_id and e.entity_kind='place' and e.identity_state='canonical'
  ) then raise exception 'Canonical Reality Place with active profile required.' using errcode='23514'; end if;

  select * into v_existing from atlas.spatial_contexts where stable_key=p_stable_key;
  if v_existing.id is not null and (v_existing.subject_kind<>p_subject_kind or v_existing.subject_id<>p_subject_id) then
    raise exception 'Spatial stable key already belongs to a different subject.' using errcode='23505';
  end if;

  insert into atlas.spatial_contexts(
    stable_key,organization_id,subject_kind,subject_id,context_kind,place_entity_id,presence_mode,
    distance_limit_meters,valid_from,valid_until,context_state,basis,metadata,retired_at
  ) values(
    p_stable_key,p_organization_id,p_subject_kind,p_subject_id,p_context_kind,p_place_entity_id,p_presence_mode,
    p_distance_limit_meters,p_valid_from,p_valid_until,'active',p_basis,p_metadata,null
  )
  on conflict (stable_key) do update set
    organization_id=excluded.organization_id,
    context_kind=excluded.context_kind,
    place_entity_id=excluded.place_entity_id,
    presence_mode=excluded.presence_mode,
    distance_limit_meters=excluded.distance_limit_meters,
    valid_from=excluded.valid_from,
    valid_until=excluded.valid_until,
    context_state='active',
    basis=excluded.basis,
    metadata=atlas.spatial_contexts.metadata || excluded.metadata,
    retired_at=null,
    updated_at=now()
  returning * into v_row;

  return jsonb_build_object(
    'contextId',v_row.id,'stableKey',v_row.stable_key,'subjectKind',v_row.subject_kind,'subjectId',v_row.subject_id,
    'contextKind',v_row.context_kind,'placeEntityId',v_row.place_entity_id,'presenceMode',v_row.presence_mode,
    'distanceLimitMeters',v_row.distance_limit_meters,'state',v_row.context_state,
    'contractVersion','spatial_context_write_v1','canonicalTruthCreated',false,'communicationAuthorized',false
  );
end
$function$;

create or replace function atlas.retire_spatial_context_service_v1(p_stable_key text,p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare v_row atlas.spatial_contexts%rowtype;
begin
  update atlas.spatial_contexts set context_state='retired',retired_at=coalesce(retired_at,now()),updated_at=now(),metadata=metadata||jsonb_build_object('retirementReason',p_reason)
  where stable_key=p_stable_key and context_state='active' returning * into v_row;
  if v_row.id is null then raise exception 'Active spatial context not found.' using errcode='P0002'; end if;
  return jsonb_build_object('contextId',v_row.id,'stableKey',v_row.stable_key,'state','retired','contractVersion','spatial_context_retirement_v1');
end
$function$;

create or replace function atlas.spatial_contexts_for_subject_service_v1(p_subject_kind text,p_subject_id uuid,p_as_of timestamptz default now())
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog','atlas','reality'
as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'contextId',c.id,'stableKey',c.stable_key,'contextKind',c.context_kind,'placeEntityId',c.place_entity_id,
    'placeName',e.display_name,'presenceMode',c.presence_mode,'distanceLimitMeters',c.distance_limit_meters,
    'validFrom',c.valid_from,'validUntil',c.valid_until,'basis',c.basis,'metadata',c.metadata
  ) order by c.context_kind,c.created_at,c.id),'[]'::jsonb)
  from atlas.spatial_contexts c
  left join reality.entities e on e.id=c.place_entity_id
  where c.subject_kind=p_subject_kind and c.subject_id=p_subject_id and c.context_state='active'
    and (c.valid_from is null or c.valid_from<=p_as_of)
    and (c.valid_until is null or p_as_of<c.valid_until);
$function$;

create or replace function geography.place_distance_service_v1(p_from_place_entity_id uuid,p_to_place_entity_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_from record;
  v_to record;
  v_meters double precision;
begin
  select * into v_from from geography.v_canonical_place_geometry_v1 where place_entity_id=p_from_place_entity_id and centroid is not null order by geometry_priority,source_vintage desc,source_feature_key limit 1;
  select * into v_to from geography.v_canonical_place_geometry_v1 where place_entity_id=p_to_place_entity_id and centroid is not null order by geometry_priority,source_vintage desc,source_feature_key limit 1;
  if v_from.place_entity_id is null or v_to.place_entity_id is null then
    return jsonb_build_object('state','geometry_required','fromPlaceEntityId',p_from_place_entity_id,'toPlaceEntityId',p_to_place_entity_id,'contractVersion','canonical_place_distance_v1');
  end if;
  v_meters:=extensions.st_distance(v_from.centroid::extensions.geography,v_to.centroid::extensions.geography);
  return jsonb_build_object(
    'state','known','fromPlaceEntityId',p_from_place_entity_id,'fromPlaceName',v_from.display_name,
    'toPlaceEntityId',p_to_place_entity_id,'toPlaceName',v_to.display_name,
    'distanceMeters',v_meters,'distanceKilometers',v_meters/1000.0,'distanceMiles',v_meters/1609.344,
    'distanceBasis','geodesic_centroid','travelTimeState','routing_source_required',
    'contractVersion','canonical_place_distance_v1'
  );
end
$function$;

create or replace function geography.place_ancestors_service_v1(p_place_entity_id uuid,p_max_depth integer default 8,p_as_of timestamptz default now())
returns table(place_entity_id uuid,display_name text,place_kind text,depth integer,path_entity_ids uuid[],path_relationship_ids uuid[],path_relationship_kinds text[])
language plpgsql
stable
security definer
set search_path to ''
as $function$
begin
  if p_max_depth<1 or p_max_depth>32 then raise exception 'Traversal depth must be between 1 and 32.' using errcode='22023'; end if;
  if not exists(select 1 from reality.entities e join reality.place_profiles pp on pp.entity_id=e.id and pp.profile_state='active' where e.id=p_place_entity_id and e.entity_kind='place' and e.identity_state='canonical') then raise exception 'Canonical Place required.' using errcode='P0002'; end if;
  return query
  select e.id,e.display_name,pp.place_kind,0,array[e.id]::uuid[],'{}'::uuid[],'{}'::text[]
  from reality.entities e join reality.place_profiles pp on pp.entity_id=e.id and pp.profile_state='active' where e.id=p_place_entity_id
  union all
  select e.id,e.display_name,pp.place_kind,p.depth,p.path_entity_ids,p.path_relationship_ids,p.path_relationship_kinds
  from reality.entity_topology_paths_service_v1(p_place_entity_id,'spatial_containment','ancestors',p_max_depth,p_as_of,true) p
  join reality.entities e on e.id=p.related_entity_id and e.entity_kind='place' and e.identity_state='canonical'
  join reality.place_profiles pp on pp.entity_id=e.id and pp.profile_state='active';
end
$function$;

create or replace function reality.entity_spatial_presence_service_v1(
  p_entity_id uuid,p_max_operating_depth integer default 8,p_max_spatial_depth integer default 8,p_as_of timestamptz default now()
)
returns table(root_entity_id uuid,presence_entity_id uuid,place_entity_id uuid,place_name text,place_kind text,operating_depth integer,spatial_depth integer,operating_path_entity_ids uuid[],spatial_path_entity_ids uuid[])
language plpgsql
stable
security definer
set search_path to ''
as $function$
begin
  if p_max_operating_depth<1 or p_max_operating_depth>32 or p_max_spatial_depth<1 or p_max_spatial_depth>32 then raise exception 'Traversal depths must be between 1 and 32.' using errcode='22023'; end if;
  if not exists(select 1 from reality.entities where id=p_entity_id and identity_state='canonical') then raise exception 'Canonical Reality Entity required.' using errcode='P0002'; end if;
  return query
  with raw_members as (
    select p_entity_id as member_id,0::integer as op_depth,array[p_entity_id]::uuid[] as op_entities
    union all
    select p.related_entity_id,p.depth,p.path_entity_ids
    from reality.entity_topology_paths_service_v1(p_entity_id,'operating_structure','descendants',p_max_operating_depth,p_as_of,true) p
  ), members as (
    select distinct on (member_id) member_id,op_depth,op_entities from raw_members order by member_id,op_depth
  ), spatial as (
    select m.member_id as presence_entity_id,m.member_id as place_id,m.op_depth,0::integer as sp_depth,m.op_entities,array[m.member_id]::uuid[] as sp_entities
    from members m join reality.entities pe on pe.id=m.member_id and pe.entity_kind='place' and pe.identity_state='canonical'
    union all
    select m.member_id,p.related_entity_id,m.op_depth,p.depth,m.op_entities,p.path_entity_ids
    from members m
    cross join lateral reality.entity_topology_paths_service_v1(m.member_id,'spatial_containment','ancestors',p_max_spatial_depth,p_as_of,true) p
    join reality.entities pe on pe.id=p.related_entity_id and pe.entity_kind='place' and pe.identity_state='canonical'
  )
  select distinct on (s.presence_entity_id,s.place_id)
    p_entity_id,s.presence_entity_id,s.place_id,e.display_name,pp.place_kind,s.op_depth,s.sp_depth,s.op_entities,s.sp_entities
  from spatial s
  join reality.entities e on e.id=s.place_id
  join reality.place_profiles pp on pp.entity_id=e.id and pp.profile_state='active'
  order by s.presence_entity_id,s.place_id,s.op_depth,s.sp_depth;
end
$function$;

create or replace function atlas.nearby_entities_service_v1(
  p_origin_place_entity_id uuid,
  p_candidate_entity_kinds text[] default array['person','business','organization']::text[],
  p_max_distance_meters double precision default 50000,
  p_max_operating_depth integer default 8,
  p_max_spatial_depth integer default 8,
  p_limit integer default 50,
  p_as_of timestamptz default now()
)
returns table(entity_id uuid,display_name text,entity_kind text,nearest_place_entity_id uuid,nearest_place_name text,distance_meters double precision,distance_miles double precision,distance_basis text)
language plpgsql
stable
security definer
set search_path to ''
as $function$
begin
  if p_max_distance_meters<0 or p_max_distance_meters>25000000 then raise exception 'Distance outside supported range.' using errcode='22023'; end if;
  if p_limit<1 or p_limit>500 then raise exception 'Limit must be between 1 and 500.' using errcode='22023'; end if;
  if not exists(select 1 from geography.v_canonical_place_geometry_v1 where place_entity_id=p_origin_place_entity_id and centroid is not null) then raise exception 'Origin canonical Place geometry required.' using errcode='P0002'; end if;
  return query
  with origin as (
    select centroid from geography.v_canonical_place_geometry_v1 where place_entity_id=p_origin_place_entity_id and centroid is not null order by geometry_priority,source_vintage desc,source_feature_key limit 1
  ), raw as (
    select e.id,e.display_name,e.entity_kind,sp.place_entity_id,sp.place_name,
      extensions.st_distance(og.centroid::extensions.geography,g.centroid::extensions.geography) as meters
    from reality.entities e
    cross join origin og
    cross join lateral reality.entity_spatial_presence_service_v1(e.id,p_max_operating_depth,p_max_spatial_depth,p_as_of) sp
    join geography.v_canonical_place_geometry_v1 g on g.place_entity_id=sp.place_entity_id and g.centroid is not null
    where e.identity_state='canonical' and e.entity_kind=any(p_candidate_entity_kinds)
  ), ranked as (
    select r.*,row_number() over(partition by r.id order by r.meters,r.place_entity_id) rn from raw r where r.meters<=p_max_distance_meters
  )
  select r.id,r.display_name,r.entity_kind,r.place_entity_id,r.place_name,r.meters,r.meters/1609.344,'geodesic_centroid'::text
  from ranked r where r.rn=1 order by r.meters,r.display_name,r.id limit p_limit;
end
$function$;

create or replace function atlas.spatial_candidate_match_service_v1(
  p_subject_kind text,p_subject_id uuid,
  p_candidate_entity_kinds text[] default array['person','business','organization']::text[],
  p_default_max_distance_meters double precision default 50000,
  p_limit integer default 50,p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare v_context atlas.spatial_contexts%rowtype; v_matches jsonb;
begin
  select * into v_context from atlas.spatial_contexts c
  where c.subject_kind=p_subject_kind and c.subject_id=p_subject_id and c.context_state='active' and c.place_entity_id is not null
    and c.context_kind in ('required_at','occurs_at','destination','service_area','preferred_near','base_at')
    and (c.valid_from is null or c.valid_from<=p_as_of) and (c.valid_until is null or p_as_of<c.valid_until)
  order by case c.context_kind when 'required_at' then 1 when 'occurs_at' then 2 when 'destination' then 3 when 'service_area' then 4 when 'preferred_near' then 5 else 6 end,c.created_at limit 1;
  if v_context.id is null then
    return jsonb_build_object('state','spatial_anchor_required','subjectKind',p_subject_kind,'subjectId',p_subject_id,'matches','[]'::jsonb,'contractVersion','spatial_candidate_match_v1');
  end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.distance_meters,x.display_name),'[]'::jsonb) into v_matches
  from atlas.nearby_entities_service_v1(v_context.place_entity_id,p_candidate_entity_kinds,coalesce(v_context.distance_limit_meters,p_default_max_distance_meters),8,8,p_limit,p_as_of) x;
  return jsonb_build_object(
    'state','ready','subjectKind',p_subject_kind,'subjectId',p_subject_id,'anchorContextKind',v_context.context_kind,
    'anchorPlaceEntityId',v_context.place_entity_id,'distanceLimitMeters',coalesce(v_context.distance_limit_meters,p_default_max_distance_meters),
    'matches',v_matches,'distanceBasis','geodesic_centroid','travelTimeState','routing_source_required','contractVersion','spatial_candidate_match_v1'
  );
end
$function$;

create or replace function atlas.spatial_work_opportunities_near_place_service_v1(
  p_place_entity_id uuid,p_organization_id uuid default null,p_max_distance_meters double precision default 25000,p_limit integer default 50,p_as_of timestamptz default now()
)
returns table(work_item_id uuid,title text,organization_id uuid,context_kind text,work_place_entity_id uuid,work_place_name text,distance_meters double precision,distance_miles double precision)
language plpgsql
stable
security definer
set search_path to ''
as $function$
begin
  if p_max_distance_meters<0 or p_max_distance_meters>25000000 then raise exception 'Distance outside supported range.' using errcode='22023'; end if;
  if p_limit<1 or p_limit>500 then raise exception 'Limit must be between 1 and 500.' using errcode='22023'; end if;
  return query
  with origin as (
    select centroid from geography.v_canonical_place_geometry_v1 where place_entity_id=p_place_entity_id and centroid is not null order by geometry_priority,source_vintage desc,source_feature_key limit 1
  ), raw as (
    select wi.id,wi.title,wi.organization_id,c.context_kind,c.place_entity_id,e.display_name as place_name,
      extensions.st_distance(o.centroid::extensions.geography,g.centroid::extensions.geography) as meters
    from atlas.work_items wi
    join atlas.spatial_contexts c on c.subject_kind='work_item' and c.subject_id=wi.id and c.context_state='active' and c.place_entity_id is not null and c.context_kind in ('required_at','occurs_at','preferred_near','service_area')
    join reality.entities e on e.id=c.place_entity_id
    join geography.v_canonical_place_geometry_v1 g on g.place_entity_id=c.place_entity_id and g.centroid is not null
    cross join origin o
    where wi.work_state='open' and (p_organization_id is null or wi.organization_id=p_organization_id)
      and (c.valid_from is null or c.valid_from<=p_as_of) and (c.valid_until is null or p_as_of<c.valid_until)
  ), ranked as (
    select r.*,row_number() over(partition by r.id order by r.meters,r.context_kind,r.place_entity_id) rn from raw r where r.meters<=p_max_distance_meters
  )
  select r.id,r.title,r.organization_id,r.context_kind,r.place_entity_id,r.place_name,r.meters,r.meters/1609.344
  from ranked r where rn=1 order by r.meters,r.title,r.id limit p_limit;
end
$function$;

revoke all on function atlas.spatial_subject_exists_v1(text,uuid) from public,anon,authenticated;
revoke all on function atlas.put_spatial_context_service_v1(text,text,uuid,text,uuid,text,double precision,timestamptz,timestamptz,uuid,jsonb,jsonb) from public,anon,authenticated;
revoke all on function atlas.retire_spatial_context_service_v1(text,text) from public,anon,authenticated;
revoke all on function atlas.spatial_contexts_for_subject_service_v1(text,uuid,timestamptz) from public,anon,authenticated;
revoke all on function geography.place_distance_service_v1(uuid,uuid) from public,anon,authenticated;
revoke all on function geography.place_ancestors_service_v1(uuid,integer,timestamptz) from public,anon,authenticated;
revoke all on function reality.entity_spatial_presence_service_v1(uuid,integer,integer,timestamptz) from public,anon,authenticated;
revoke all on function atlas.nearby_entities_service_v1(uuid,text[],double precision,integer,integer,integer,timestamptz) from public,anon,authenticated;
revoke all on function atlas.spatial_candidate_match_service_v1(text,uuid,text[],double precision,integer,timestamptz) from public,anon,authenticated;
revoke all on function atlas.spatial_work_opportunities_near_place_service_v1(uuid,uuid,double precision,integer,timestamptz) from public,anon,authenticated;

grant execute on function atlas.spatial_subject_exists_v1(text,uuid) to service_role;
grant execute on function atlas.put_spatial_context_service_v1(text,text,uuid,text,uuid,text,double precision,timestamptz,timestamptz,uuid,jsonb,jsonb) to service_role;
grant execute on function atlas.retire_spatial_context_service_v1(text,text) to service_role;
grant execute on function atlas.spatial_contexts_for_subject_service_v1(text,uuid,timestamptz) to service_role;
grant execute on function geography.place_distance_service_v1(uuid,uuid) to service_role;
grant execute on function geography.place_ancestors_service_v1(uuid,integer,timestamptz) to service_role;
grant execute on function reality.entity_spatial_presence_service_v1(uuid,integer,integer,timestamptz) to service_role;
grant execute on function atlas.nearby_entities_service_v1(uuid,text[],double precision,integer,integer,integer,timestamptz) to service_role;
grant execute on function atlas.spatial_candidate_match_service_v1(text,uuid,text[],double precision,integer,timestamptz) to service_role;
grant execute on function atlas.spatial_work_opportunities_near_place_service_v1(uuid,uuid,double precision,integer,timestamptz) to service_role;
